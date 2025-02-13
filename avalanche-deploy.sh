#!/bin/bash

# Check if running on Ubuntu Server
check_ubuntu_server() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        echo "This script requires Ubuntu Server."
        exit 1
    fi
    
    # Check Ubuntu version
    ubuntu_version=$(lsb_release -rs)
    if ! [[ "$ubuntu_version" =~ ^(20.04|22.04)$ ]]; then
        echo "This script requires Ubuntu Server 20.04 or 22.04 LTS."
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root (use sudo)"
        exit 1
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    echo -e "${2}${1}${NC}"
}

# Function to create avalanche user if it doesn't exist
create_avalanche_user() {
    if ! id -u avalanche >/dev/null 2>&1; then
        useradd -m -s /bin/bash avalanche || {
            print_message "Failed to create avalanche user" "$RED"
            exit 1
        }
    fi
}

# Function to install system dependencies
install_dependencies() {
    print_message "Installing system dependencies..." "$YELLOW"
    apt-get update || {
        print_message "Failed to update package lists" "$RED"
        exit 1
    }
    
    # Install required packages
    apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        tar \
        lsb-release \
        ufw \
        fail2ban \
        jq \
        bc \
        || {
        print_message "Failed to install required packages" "$RED"
        exit 1
    }
}

# Function to get public IP
get_public_ip() {
    curl -s https://api.ipify.org
}

# Function to configure network environment
configure_network() {
    # Check for existing configuration
    if [ -f "/home/avalanche/.avalanchego/config.json" ]; then
        read -p "Existing configuration found. Override? [y/n]: " override
        if [ "$override" != "y" ]; then
            print_message "Keeping existing configuration" "$YELLOW"
            return 0
        fi
    fi

    print_message "\nNetwork Configuration" "$GREEN"
    echo "----------------------------------------"
    echo "Where is the node installed:"
    echo "1) residential network (dynamic IP)"
    echo "2) cloud provider (static IP)"
    read -p "Enter your connection type [1,2]: " connection_type

    case $connection_type in
        1)
            NODE_IP="dynamic"
            ;;
        2)
            detected_ip=$(get_public_ip)
            echo "Detected '${detected_ip}' as your public IP. Is this correct? [y,n]:"
            read ip_correct
            if [ "$ip_correct" = "y" ]; then
                NODE_IP=$detected_ip
            else
                read -p "Please enter your static IP: " NODE_IP
            fi
            ;;
        *)
            print_message "Invalid choice" "$RED"
            exit 1
            ;;
    esac

    # Configure RPC access based on node type
    if [ "$NODE_TYPE" = "validator" ]; then
        RPC_ACCESS="private"
    else
        echo -e "\nRPC port should be public (this is a public API node) or private (this is a validator)? [public, private]:"
        read RPC_ACCESS
        if [ "$RPC_ACCESS" = "public" ]; then
            print_message "\nWARNING: Public RPC access requires proper firewall configuration!" "$YELLOW"
            read -p "Are you sure you want to continue? [y/n]: " confirm
            if [ "$confirm" != "y" ]; then
                exit 1
            fi
        fi
    fi

    # Configure state sync based on node type
    if [ "$NODE_TYPE" = "archive" ]; then
        STATE_SYNC="off"
    else
        echo -e "\nDo you want state sync bootstrapping to be turned on or off? [on, off]:"
        read STATE_SYNC
    fi

    # Save configuration
    mkdir -p /home/avalanche/.avalanchego
    cat > /home/avalanche/.avalanchego/config.json << EOF
{
    "network_type": "$connection_type",
    "node_ip": "$NODE_IP",
    "rpc_access": "$RPC_ACCESS"
}
EOF
}

# Function to get latest AvalancheGo version
get_latest_version() {
    curl -s https://api.github.com/repos/ava-labs/avalanchego/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")'
}

# Function to configure firewall
configure_firewall() {
    print_message "Configuring firewall..." "$YELLOW"
    apt-get install -y ufw
    ufw allow 22/tcp
    ufw allow 9651/tcp
    
    if [ "$RPC_ACCESS" = "public" ]; then
        ufw allow 9650/tcp
    fi
    
    ufw --force enable
}

# Function to create systemd service
create_systemd_service() {
    local extra_args="$1"
    
    # Build configuration based on node type and settings
    if [ "$RPC_ACCESS" = "private" ]; then
        extra_args="$extra_args --http.addr=127.0.0.1"
    else
        extra_args="$extra_args --http.addr=0.0.0.0"
    fi

    if [ "$STATE_SYNC" = "off" ]; then
        extra_args="$extra_args --state-sync-disabled=true"
    fi

    if [ "$NODE_IP" != "dynamic" ]; then
        extra_args="$extra_args --public-ip=$NODE_IP"
    fi

    # Enable indexing for RPC nodes
    if [ "$NODE_TYPE" = "archive" ] || [ "$NODE_TYPE" = "api" ]; then
        extra_args="$extra_args --index-enabled=true"
    fi

    # Create systemd service with proper security settings
    cat > /etc/systemd/system/avalanchego.service << EOF
[Unit]
Description=AvalancheGo systemd service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=avalanche
Group=avalanche
WorkingDirectory=/home/avalanche
ExecStart=/home/avalanche/avalanchego/avalanchego $extra_args
LimitNOFILE=32768
Restart=always
RestartSec=1
TimeoutStopSec=300

# Security settings
ProtectSystem=full
ProtectHome=read-only
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
EOF

    # Set proper permissions
    chown root:root /etc/systemd/system/avalanchego.service
    chmod 644 /etc/systemd/system/avalanchego.service

    # Create and set permissions for required directories
    mkdir -p /home/avalanche/.avalanchego
    mkdir -p /home/avalanche/avalanchego
    chown -R avalanche:avalanche /home/avalanche/.avalanchego
    chown -R avalanche:avalanche /home/avalanche/avalanchego
    chmod 750 /home/avalanche/.avalanchego
    chmod 750 /home/avalanche/avalanchego

    systemctl daemon-reload
    systemctl enable avalanchego
}

# Function to install AvalancheGo
install_avalanchego() {
    print_message "Installing AvalancheGo..." "$YELLOW"
    
    # Check if already installed
    if [ -d "/home/avalanche/.avalanchego" ]; then
        print_message "AvalancheGo installation detected. Checking version..." "$YELLOW"
        current_version=$(avalanchego --version 2>/dev/null | grep -oP 'avalanchego/[0-9]+\.[0-9]+\.[0-9]+' | cut -d'/' -f2)
        latest_version=$(curl -s https://api.github.com/repos/ava-labs/avalanchego/releases/latest | grep -oP '"tag_name": "v\K[^"]*')
        
        if [ -n "$current_version" ] && [ -n "$latest_version" ]; then
            if [ "$current_version" = "$latest_version" ]; then
                print_message "Current version ($current_version) is up to date" "$GREEN"
                read -p "Reinstall anyway? [y/n]: " reinstall
                if [ "$reinstall" != "y" ]; then
                    return 0
                fi
            else
                print_message "New version available: $latest_version (current: $current_version)" "$YELLOW"
            fi
        fi
    fi
    
    # Download installer with retry mechanism
    for i in {1..3}; do
        if wget -nd -m https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/avalanchego-installer.sh; then
            break
        else
            if [ $i -lt 3 ]; then
                print_message "Download attempt $i failed. Retrying..." "$YELLOW"
                sleep 5
            else
                print_message "Failed to download Avalanche installer script" "$RED"
                exit 1
            fi
        fi
    done
    
    chmod 755 avalanchego-installer.sh || {
        print_message "Failed to set installer permissions" "$RED"
        exit 1
    }

    # Create answers file for automated installation
    cat > installer_answers.txt << EOF
$connection_type
$NODE_IP
$RPC_ACCESS
$STATE_SYNC
EOF

    # Run installer with predefined answers
    if ! cat installer_answers.txt | ./avalanchego-installer.sh; then
        print_message "Avalanche installer failed" "$RED"
        rm installer_answers.txt
        exit 1
    fi
    
    # Clean up
    rm -f installer_answers.txt avalanchego-installer.sh

    # Verify installation
    if ! command -v avalanchego &> /dev/null; then
        print_message "AvalancheGo binary not found after installation" "$RED"
        exit 1
    fi

    # Verify service is running
    sleep 5
    if ! systemctl is-active --quiet avalanchego; then
        print_message "AvalancheGo service failed to start" "$RED"
        exit 1
    fi

    print_message "AvalancheGo installation completed successfully" "$GREEN"
}

# Function to configure node based on type
configure_node() {
    local config_args="--http.port=9650"
    create_systemd_service "$config_args"
}

# Function to configure security
configure_security() {
    print_message "Configuring security settings..." "$YELLOW"
    
    # Set proper file permissions for staking files
    if [ -d "/home/avalanche/.avalanchego/staking" ]; then
        # Ensure directory exists with proper permissions
        mkdir -p /home/avalanche/.avalanchego/staking
        chown -R avalanche:avalanche /home/avalanche/.avalanchego/staking
        chmod 700 /home/avalanche/.avalanchego/staking || {
            print_message "Failed to set staking directory permissions" "$RED"
            exit 1
        }
        
        # Set permissions for key files if they exist
        for file in staker.key staker.crt signer.key; do
            if [ -f "/home/avalanche/.avalanchego/staking/$file" ]; then
                chown avalanche:avalanche "/home/avalanche/.avalanchego/staking/$file"
                chmod 600 "/home/avalanche/.avalanchego/staking/$file" || {
                    print_message "Failed to set $file permissions" "$RED"
                    exit 1
                }
            fi
        done
    fi
    
    # Configure system limits
    cat > /etc/security/limits.d/avalanche.conf << EOF
avalanche soft nofile 32768
avalanche hard nofile 65536
EOF

    # Configure sysctl parameters
    cat > /etc/sysctl.d/99-avalanche.conf << EOF
net.core.rmem_max=2500000
net.core.wmem_max=2500000
EOF
    sysctl -p /etc/sysctl.d/99-avalanche.conf

    # Install and configure fail2ban if public access
    if [ "$RPC_ACCESS" = "public" ]; then
        print_message "Installing fail2ban for additional security..." "$YELLOW"
        apt-get install -y fail2ban || {
            print_message "Failed to install fail2ban" "$RED"
            exit 1
        }

        # Configure fail2ban for Avalanche
        cat > /etc/fail2ban/jail.d/avalanche.conf << EOF
[avalanche]
enabled = true
port = 9650
filter = avalanche
logpath = /var/log/syslog
maxretry = 5
findtime = 300
bantime = 3600
EOF

        # Create fail2ban filter for Avalanche
        cat > /etc/fail2ban/filter.d/avalanche.conf << EOF
[Definition]
failregex = ^.*Invalid token:.*from <HOST>
            ^.*Too many requests:.*from <HOST>
ignoreregex =
EOF

        systemctl enable fail2ban || {
            print_message "Failed to enable fail2ban" "$RED"
            exit 1
        }
        systemctl restart fail2ban || {
            print_message "Failed to start fail2ban" "$RED"
            exit 1
        }
    fi
}

# Function to perform backup
perform_backup() {
    print_message "\nAvalanche Node Backup" "$GREEN"
    echo "----------------------------------------"
    
    # Create timestamped backup directory
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR=~/avalanche_backup/${TIMESTAMP}
    mkdir -p $BACKUP_DIR || {
        print_message "Failed to create backup directory" "$RED"
        return 1
    }
    
    echo "Select backup type:"
    echo "1) Node identity files only"
    echo "2) Full database backup"
    read -p "Enter choice (1-2): " backup_type

    # Backup staking files
    if [ -d "/home/avalanche/.avalanchego/staking" ]; then
        cp -r /home/avalanche/.avalanchego/staking $BACKUP_DIR/ || {
            print_message "Failed to copy staking files" "$RED"
            return 1
        }
    else
        print_message "Error: Staking directory not found" "$RED"
        return 1
    fi

    # Perform database backup if selected
    if [ "$backup_type" = "2" ]; then
        print_message "Performing database backup..." "$YELLOW"
        
        # Stop the node
        systemctl stop avalanchego || {
            print_message "Failed to stop avalanchego service" "$RED"
            return 1
        }
        
        # Create database backup
        if [ -d "/home/avalanche/.avalanchego/db" ]; then
            tar czf "$BACKUP_DIR/db_backup.tar.gz" -C /home/avalanche/.avalanchego db || {
                print_message "Failed to create database archive" "$RED"
                systemctl start avalanchego
                return 1
            }
        fi
        
        # Start the node
        systemctl start avalanchego
        
        # Verify node is running
        sleep 5
        if ! systemctl is-active --quiet avalanchego; then
            print_message "Failed to restart avalanchego service" "$RED"
            return 1
        }
    fi
    
    print_message "Backup completed successfully to $BACKUP_DIR" "$GREEN"
    return 0
}

# Function to restore backup
perform_restore() {
    print_message "\nAvalanche Node Restore" "$GREEN"
    echo "----------------------------------------"
    
    # Select backup directory
    read -p "Enter backup directory path: " backup_dir
    
    if [ ! -d "$backup_dir" ]; then
        print_message "Invalid backup directory" "$RED"
        return 1
    fi
    
    # Stop the node
    systemctl stop avalanchego || {
        print_message "Failed to stop avalanchego service" "$RED"
        return 1
    }
    
    # Backup existing files before restore
    if [ -d "/home/avalanche/.avalanchego/staking" ]; then
        mv /home/avalanche/.avalanchego/staking /home/avalanche/.avalanchego/staking-old || {
            print_message "Failed to backup existing staking files" "$RED"
            systemctl start avalanchego
            return 1
        }
    fi
    
    # Restore staking files
    if [ -d "$backup_dir/staking" ]; then
        cp -r "$backup_dir/staking" /home/avalanche/.avalanchego/ || {
            print_message "Failed to restore staking files" "$RED"
            systemctl start avalanchego
            return 1
        }
    fi
    
    # Restore database if backup exists
    if [ -f "$backup_dir/db_backup.tar.gz" ]; then
        print_message "Restoring database..." "$YELLOW"
        
        # Backup existing database
        if [ -d "/home/avalanche/.avalanchego/db" ]; then
            mv /home/avalanche/.avalanchego/db /home/avalanche/.avalanchego/db-old || {
                print_message "Failed to backup existing database" "$RED"
                systemctl start avalanchego
                return 1
            }
        fi
        
        # Extract database backup
        tar xzf "$backup_dir/db_backup.tar.gz" -C /home/avalanche/.avalanchego/ || {
            print_message "Failed to restore database" "$RED"
            systemctl start avalanchego
            return 1
        }
    fi
    
    # Fix permissions
    chown -R avalanche:avalanche /home/avalanche/.avalanchego
    chmod 700 /home/avalanche/.avalanchego/staking
    chmod 600 /home/avalanche/.avalanchego/staking/*
    
    # Start the node
    systemctl start avalanchego
    
    # Verify node is running
    sleep 5
    if ! systemctl is-active --quiet avalanchego; then
        print_message "Failed to restart avalanchego service" "$RED"
        return 1
    fi
    
    print_message "Restore completed successfully" "$GREEN"
    return 0
}

# Function to detect existing deployment
detect_existing_deployment() {
    print_message "Checking for existing Avalanche deployment..." "$YELLOW"
    
    # Check for common installation paths and files
    if [ -d "/home/avalanche/.avalanchego" ] || [ -d "/home/avalanche/avalanchego" ] || [ -f "/etc/systemd/system/avalanchego.service" ]; then
        print_message "Existing Avalanche deployment detected!" "$YELLOW"
        
        echo "----------------------------------------"
        echo "Deployment Details:"
        
        # Display current configuration
        if [ -f "/home/avalanche/.avalanchego/config.json" ]; then
            source /home/avalanche/.avalanchego/config.json
            print_message "Node Type: $NODE_TYPE" "$YELLOW"
            print_message "RPC Access: $RPC_ACCESS" "$YELLOW"
            print_message "State Sync: $STATE_SYNC" "$YELLOW"
        fi
        
        # Check service status
        if systemctl is-active --quiet avalanchego; then
            print_message "Service Status: Running" "$GREEN"
        else
            print_message "Service Status: Not Running" "$RED"
        fi
        
        echo "----------------------------------------"
        echo "Available Actions:"
        echo "B) Backup existing deployment"
        echo "U) Upgrade node"
        echo "R) Restore from backup"
        echo "C) Cancel"
        read -p "Select action [B/U/R/C]: " action
        case $action in
            [Bb])
                perform_backup
                ;;
            [Uu])
                if systemctl is-active --quiet avalanchego; then
                    print_message "Please stop the node before upgrade" "$RED"
                    read -p "Stop node now? [y/n]: " stop_node
                    if [ "$stop_node" = "y" ]; then
                        systemctl stop avalanchego
                    else
                        exit 1
                    fi
                fi
                install_avalanchego
                ;;
            [Rr])
                perform_restore
                ;;
            *)
                print_message "Operation cancelled by user" "$YELLOW"
                exit 1
                ;;
        esac
    fi
    
    return 0
}

# Main script execution
main() {
    clear
    
    # Run initial checks
    check_ubuntu_server
    check_root
    
    # Create avalanche user
    create_avalanche_user
    
    # Install dependencies
    install_dependencies
    
    # Detect existing deployment
    detect_existing_deployment
    
    # Configure network
    configure_network
    
    # Install AvalancheGo
    install_avalanchego
    
    # Configure node
    configure_node
    
    # Configure security
    configure_security
    
    # Start service
    systemctl start avalanchego
    
    print_message "\nInstallation Complete!" "$GREEN"
    echo "----------------------------------------"
    
    # Display node information and commands
    display_node_info
}

# Function to display node information
display_node_info() {
    # Wait for node to start and get NodeID
    sleep 10
    NODE_ID=$(journalctl -u avalanchego | grep "NodeID" | tail -n 1 | grep -oP "NodeID-\K[a-zA-Z0-9]+")
    if [ -n "$NODE_ID" ]; then
        print_message "\nNode Information:" "$GREEN"
        print_message "NodeID: NodeID-$NODE_ID" "$YELLOW"
    fi
    
    print_message "\nNode Management Commands:" "$GREEN"
    echo "----------------------------------------"
    print_message "Start node:   sudo systemctl start avalanchego" "$YELLOW"
    print_message "Stop node:    sudo systemctl stop avalanchego" "$YELLOW"
    print_message "Restart node: sudo systemctl restart avalanchego" "$YELLOW"
    print_message "Node status:  sudo systemctl status avalanchego" "$YELLOW"
    
    print_message "\nMonitoring Commands:" "$GREEN"
    echo "----------------------------------------"
    print_message "View all logs:        sudo journalctl -u avalanchego" "$YELLOW"
    print_message "Follow live logs:     sudo journalctl -u avalanchego -f" "$YELLOW"
    print_message "View recent logs:     sudo journalctl -u avalanchego -n 100" "$YELLOW"
    print_message "View logs by time:    sudo journalctl -u avalanchego --since '1 hour ago'" "$YELLOW"
    
    print_message "\nNode Configuration:" "$GREEN"
    echo "----------------------------------------"
    print_message "Config directory:     /home/avalanche/.avalanchego" "$YELLOW"
    print_message "Binary location:      /home/avalanche/avalanchego/avalanchego" "$YELLOW"
    print_message "Service file:         /etc/systemd/system/avalanchego.service" "$YELLOW"
    
    if [ "$RPC_ACCESS" = "public" ]; then
        print_message "\nRPC Endpoints:" "$GREEN"
        echo "----------------------------------------"
        print_message "HTTP RPC:     http://$NODE_IP:9650" "$YELLOW"
        print_message "Staking Port: :9651" "$YELLOW"
    fi
    
    print_message "\nImportant Backup Information:" "$GREEN"
    echo "----------------------------------------"
    print_message "Your node's identity is defined by these critical files:" "$YELLOW"
    print_message "Location: /home/avalanche/.avalanchego/staking/" "$YELLOW"
    print_message "Files to backup:" "$YELLOW"
    print_message "  - staker.crt  (Node certificate)" "$YELLOW"
    print_message "  - staker.key  (Node private key)" "$YELLOW"
    print_message "  - signer.key  (BLS key)" "$YELLOW"
}

# Call main function if no arguments provided
if [ $# -eq 0 ]; then
    main
fi 