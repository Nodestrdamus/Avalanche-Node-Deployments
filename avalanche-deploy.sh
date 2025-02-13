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
    echo "3) Direct database copy (for large databases)"
    read -p "Enter choice (1-3): " backup_type

    echo "Select backup method:"
    echo "1) Local backup"
    echo "2) Remote backup (using scp)"
    read -p "Enter choice (1-2): " backup_choice

    case $backup_choice in
        1)
            if [ -d "/home/avalanche/.avalanchego/staking" ]; then
                # Copy staking files
                cp /home/avalanche/.avalanchego/staking/{staker.key,staker.crt,signer.key} $BACKUP_DIR/ || {
                    print_message "Failed to copy staking files" "$RED"
                    return 1
                }
                
                # Perform database backup if selected
                if [ "$backup_type" = "2" ]; then
                    perform_db_backup "$BACKUP_DIR" "archive" || return 1
                elif [ "$backup_type" = "3" ]; then
                    perform_db_backup "$BACKUP_DIR" "direct" || return 1
                fi
                
                print_message "Backup completed successfully to $BACKUP_DIR" "$GREEN"
            else
                print_message "Error: Staking directory not found" "$RED"
                return 1
            fi
            ;;
        2)
            read -p "Enter remote node IP address: " remote_ip
            read -p "Enter remote username (default: ubuntu): " remote_user
            read -p "Enter path to SSH key (optional): " ssh_key
            remote_user=${remote_user:-ubuntu}
            
            scp_cmd="scp -r"
            ssh_cmd="ssh"
            if [ ! -z "$ssh_key" ]; then
                scp_cmd="scp -i $ssh_key -r"
                ssh_cmd="ssh -i $ssh_key"
            fi
            
            print_message "Attempting remote backup..." "$YELLOW"
            if [ "$backup_type" = "1" ]; then
                $scp_cmd ${remote_user}@${remote_ip}:/home/avalanche/.avalanchego/staking $BACKUP_DIR/ || {
                    print_message "Remote backup failed" "$RED"
                    return 1
                }
            elif [ "$backup_type" = "2" ]; then
                # Stop remote node for database backup
                $ssh_cmd ${remote_user}@${remote_ip} "sudo systemctl stop avalanchego"
                
                # Backup both staking files and database
                $scp_cmd ${remote_user}@${remote_ip}:/home/avalanche/.avalanchego/staking $BACKUP_DIR/ || {
                    print_message "Failed to backup staking files" "$RED"
                    $ssh_cmd ${remote_user}@${remote_ip} "sudo systemctl start avalanchego"
                    return 1
                }
                
                $scp_cmd ${remote_user}@${remote_ip}:/home/avalanche/.avalanchego/db $BACKUP_DIR/ || {
                    print_message "Failed to backup database" "$RED"
                    $ssh_cmd ${remote_user}@${remote_ip} "sudo systemctl start avalanchego"
                    return 1
                }
                
                # Start remote node
                $ssh_cmd ${remote_user}@${remote_ip} "sudo systemctl start avalanchego"
            elif [ "$backup_type" = "3" ]; then
                # Direct copy method for large databases
                perform_db_backup "$BACKUP_DIR" "direct" "$ssh_key" || return 1
            fi
            
            print_message "Remote backup completed successfully to $BACKUP_DIR" "$GREEN"
            ;;
        *)
            print_message "Invalid choice" "$RED"
            return 1
            ;;
    esac
    return 0
}

# Function to perform database backup
perform_db_backup() {
    local backup_dir="$1"
    print_message "Performing database backup..." "$YELLOW"
    
    # Stop the node
    systemctl stop avalanchego || {
        print_message "Failed to stop avalanchego service" "$RED"
        return 1
    }
    
    # Create database backup
    if [ "$2" = "direct" ]; then
        # Direct copy method
        ssh -i "$3" ${remote_user}@${remote_ip} "tar czf - .avalanchego/db" | tar xvzf - -C "$backup_dir" || {
            print_message "Failed to perform direct database copy" "$RED"
            systemctl start avalanchego
            return 1
        }
    else
        # Archive method
        tar czf "$backup_dir/db_backup.tar.gz" /home/avalanche/.avalanchego/db || {
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
    fi
    
    return 0
}

# Function to perform database restore
perform_db_restore() {
    local backup_dir="$1"
    print_message "Performing database restore..." "$YELLOW"
    
    # Stop the node
    systemctl stop avalanchego || {
        print_message "Failed to stop avalanchego service" "$RED"
        return 1
    }
    
    # Backup existing database
    if [ -d "/home/avalanche/.avalanchego/db" ]; then
        mv /home/avalanche/.avalanchego/db /home/avalanche/.avalanchego/db-old || {
            print_message "Failed to backup existing database" "$RED"
            systemctl start avalanchego
            return 1
        }
    fi
    
    # Restore database
    if [ -f "$backup_dir/db_backup.tar.gz" ]; then
        tar xzf "$backup_dir/db_backup.tar.gz" -C /home/avalanche/.avalanchego/ || {
            print_message "Failed to restore database from archive" "$RED"
            systemctl start avalanchego
            return 1
        }
    elif [ -d "$backup_dir/db" ]; then
        cp -r "$backup_dir/db" /home/avalanche/.avalanchego/ || {
            print_message "Failed to restore database from directory" "$RED"
            systemctl start avalanchego
            return 1
        }
    else
        print_message "No valid database backup found" "$RED"
        systemctl start avalanchego
        return 1
    fi
    
    # Fix permissions
    chown -R avalanche:avalanche /home/avalanche/.avalanchego/db
    
    # Start the node
    systemctl start avalanchego
    
    # Verify node is running
    sleep 5
    if ! systemctl is-active --quiet avalanchego; then
        print_message "Failed to restart avalanchego service" "$RED"
        return 1
    }
    
    return 0
}

# Function to detect existing deployment
detect_existing_deployment() {
    print_message "Checking for existing Avalanche deployment..." "$YELLOW"
    
    local EXISTING_DEPLOYMENT=false
    local MANAGED_BY_SCRIPT=false
    local NEEDS_MIGRATION=false
    
    # Check for common installation paths and files
    local CHECK_PATHS=(
        "/home/avalanche/.avalanchego"
        "/home/avalanche/avalanchego"
        "/home/avalanche/.avalanchego/staking"
        "/etc/systemd/system/avalanchego.service"
    )
    
    for path in "${CHECK_PATHS[@]}"; do
        if [ -e "$path" ]; then
            EXISTING_DEPLOYMENT=true
            break
        fi
    done
    
    if [ "$EXISTING_DEPLOYMENT" = true ]; then
        print_message "Existing Avalanche deployment detected!" "$YELLOW"
        
        # Check if it was deployed by this script
        if grep -q "# Managed by avalanche-deploy.sh" /etc/systemd/system/avalanchego.service 2>/dev/null; then
            MANAGED_BY_SCRIPT=true
        fi
        
        echo "----------------------------------------"
        echo "Deployment Details:"
        
        # Display current configuration
        print_message "Node Type: $NODE_TYPE" "$YELLOW"
        print_message "RPC Access: $RPC_ACCESS" "$YELLOW"
        print_message "State Sync: $STATE_SYNC" "$YELLOW"
        
        # Check service status
        if systemctl is-active --quiet avalanchego; then
            print_message "Service Status: Running" "$GREEN"
        else
            print_message "Service Status: Not Running" "$RED"
        fi
        
        echo "----------------------------------------"
        if [ "$MANAGED_BY_SCRIPT" = true ]; then
            print_message "This deployment was managed by avalanche-deploy.sh" "$GREEN"
        else
            print_message "This appears to be a manual or third-party deployment" "$YELLOW"
            NEEDS_MIGRATION=true
        fi
        
        if [ "$NEEDS_MIGRATION" = true ]; then
            print_message "\nThis deployment needs migration to be fully managed by this script" "$YELLOW"
            print_message "Migration will:" "$YELLOW"
            echo "1. Backup all existing files"
            echo "2. Update service configuration"
            echo "3. Fix file permissions"
            echo "4. Add monitoring capabilities"
            echo "5. Enable script management"
        fi
        
        echo "----------------------------------------"
        echo "Available Actions:"
        echo "B) Backup existing deployment"
        echo "M) Migrate to script management"
        echo "U) Upgrade node"
        echo "C) Cancel"
        read -p "Select action [B/M/U/C]: " action
        case $action in
            [Bb])
                print_message "Backing up existing deployment..." "$YELLOW"
                perform_backup
                ;;
            [Mm])
                if systemctl is-active --quiet avalanchego; then
                    print_message "Please stop the node before migration" "$RED"
                    read -p "Stop node now? [y/n]: " stop_node
                    if [ "$stop_node" = "y" ]; then
                        systemctl stop avalanchego
                    else
                        exit 1
                    fi
                fi
                
                print_message "Starting migration process..." "$YELLOW"
                perform_backup
                configure_node
                configure_security
                print_message "Migration completed successfully" "$GREEN"
                ;;
            [Uu])
                print_message "Proceeding with upgrade..." "$YELLOW"
                install_avalanchego
                ;;
            *)
                print_message "Operation cancelled by user" "$YELLOW"
                exit 1
                ;;
        esac
    fi
    
    return 0
}

# Main script
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

# Run main script
main

# Function to analyze existing service configuration
analyze_service_config() {
    local service_file="/etc/systemd/system/avalanchego.service"
    local config_found=false
    local rpc_access="private"
    local state_sync="on"
    local node_type="validator"
    
    if [ -f "$service_file" ]; then
        # Extract existing configuration from service file
        local exec_line=$(grep "^ExecStart=" "$service_file")
        
        # Determine node type based on configuration
        if echo "$exec_line" | grep -q "index-enabled=true"; then
            if echo "$exec_line" | grep -q "state-sync-disabled=true"; then
                node_type="archive"
            else
                node_type="api"
            fi
        fi
        
        # Determine RPC access
        if echo "$exec_line" | grep -q "http.addr=0.0.0.0"; then
            rpc_access="public"
        fi
        
        # Check state sync
        if echo "$exec_line" | grep -q "state-sync-disabled=true"; then
            state_sync="off"
        fi
        
        config_found=true
    fi
    
    echo "NODE_TYPE=$node_type"
    echo "RPC_ACCESS=$rpc_access"
    echo "STATE_SYNC=$state_sync"
    echo "CONFIG_FOUND=$config_found"
}

# Function to check version compatibility
check_versions() {
    print_message "Checking version compatibility..." "$YELLOW"
    
    # Check kernel version
    KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
    if (( $(echo "$KERNEL_VERSION < 5.4" | bc -l) )); then
        print_message "Kernel version too old. Minimum required: 5.4" "$RED"
        exit 1
    fi
    
    # Check Ubuntu version
    if ! grep -q "Ubuntu 2[02].04" /etc/os-release; then
        print_message "Unsupported Ubuntu version. Use 20.04 or 22.04 LTS" "$RED"
        exit 1
    fi
}

# Function to install and configure Prometheus
install_prometheus() {
    print_message "Installing Prometheus..." "$YELLOW"
    
    # Download and install Prometheus
    wget -nd -m https://raw.githubusercontent.com/ava-labs/avalanche-monitoring/main/grafana/monitoring-installer.sh || {
        print_message "Failed to download monitoring installer script" "$RED"
        exit 1
    }
    chmod 755 monitoring-installer.sh || {
        print_message "Failed to set installer permissions" "$RED"
        exit 1
    }
    
    # Run installer steps
    ./monitoring-installer.sh --1 || {
        print_message "Failed to install Prometheus" "$RED"
        exit 1
    }
    
    # Verify Prometheus is running
    if ! systemctl is-active --quiet prometheus; then
        print_message "Prometheus installation failed" "$RED"
        exit 1
    fi
    
    # Configure firewall for Prometheus if needed
    ufw allow 9090/tcp
}

# Function to install and configure Grafana
install_grafana() {
    print_message "Installing Grafana..." "$YELLOW"
    
    # Install Grafana
    ./monitoring-installer.sh --2 || {
        print_message "Failed to install Grafana" "$RED"
        exit 1
    }
    
    # Verify Grafana is running
    if ! systemctl is-active --quiet grafana-server; then
        print_message "Grafana installation failed" "$RED"
        exit 1
    }
    
    # Configure firewall for Grafana
    ufw allow 3000/tcp
}

# Function to install and configure node_exporter
install_node_exporter() {
    print_message "Installing node_exporter..." "$YELLOW"
    
    # Install node_exporter
    ./monitoring-installer.sh --3 || {
        print_message "Failed to install node_exporter" "$RED"
        exit 1
    }
    
    # Verify node_exporter is running
    if ! systemctl is-active --quiet node_exporter; then
        print_message "node_exporter installation failed" "$RED"
        exit 1
    }
}

# Function to install Avalanche dashboards
install_dashboards() {
    print_message "Installing Avalanche dashboards..." "$YELLOW"
    
    # Install main dashboards
    ./monitoring-installer.sh --4 || {
        print_message "Failed to install main dashboards" "$RED"
        exit 1
    }
    
    # Install additional dashboards
    ./monitoring-installer.sh --5 || {
        print_message "Failed to install additional dashboards" "$RED"
        exit 1
    }
}

# Function to install monitoring prerequisites
install_monitoring_prerequisites() {
    print_message "Installing monitoring prerequisites..." "$YELLOW"
    
    # Update package lists
    apt-get update || {
        print_message "Failed to update package lists" "$RED"
        return 1
    }
    
    # Install required packages
    apt-get install -y \
        apt-transport-https \
        software-properties-common \
        wget \
        curl \
        gnupg2 \
        bc \
        jq \
        python3 \
        python3-pip \
        net-tools \
        sysstat \
        || {
        print_message "Failed to install basic prerequisites" "$RED"
        return 1
    }

    # Install Python packages for monitoring
    pip3 install \
        prometheus_client \
        requests \
        psutil \
        || {
        print_message "Failed to install Python packages" "$RED"
        return 1
    }

    # Add Grafana repository
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - || {
        print_message "Failed to add Grafana repository key" "$RED"
        return 1
    }
    
    echo "deb https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list || {
        print_message "Failed to add Grafana repository" "$RED"
        return 1
    }

    # Update package lists again after adding new repository
    apt-get update || {
        print_message "Failed to update package lists after adding Grafana repository" "$RED"
        return 1
    }

    # Install additional monitoring tools
    apt-get install -y \
        prometheus \
        prometheus-node-exporter \
        grafana \
        collectd \
        || {
        print_message "Failed to install monitoring tools" "$RED"
        return 1
    }

    print_message "Successfully installed monitoring prerequisites" "$GREEN"
    return 0
}

# Main monitoring setup function
setup_monitoring() {
    print_message "\nSetting up monitoring tools..." "$GREEN"
    echo "----------------------------------------"
    
    # Install prerequisites
    install_monitoring_prerequisites || {
        print_message "Failed to install monitoring prerequisites" "$RED"
        exit 1
    }
    
    # Check prerequisites
    check_monitoring_prerequisites || {
        print_message "Failed to meet monitoring prerequisites" "$RED"
        exit 1
    }
    
    # Install components
    install_prometheus || {
        print_message "Failed to install Prometheus" "$RED"
        exit 1
    }
    
    install_grafana || {
        print_message "Failed to install Grafana" "$RED"
        exit 1
    }
    
    install_node_exporter || {
        print_message "Failed to install node_exporter" "$RED"
        exit 1
    }
    
    install_dashboards || {
        print_message "Failed to install dashboards" "$RED"
        exit 1
    }
    
    # Configure security
    configure_monitoring_security || {
        print_message "Failed to configure monitoring security" "$RED"
        exit 1
    }
    
    # Clean up installer script
    rm -f monitoring-installer.sh
    
    # Configure data retention
    cat >> /etc/prometheus/prometheus.yml << EOF
storage:
  tsdb:
    retention.time: 30d
    retention.size: 50GB
EOF
    
    # Restart services to apply changes
    systemctl restart prometheus grafana-server node_exporter
    
    print_message "\nMonitoring setup completed!" "$GREEN"
    echo "----------------------------------------"
    print_message "Prometheus: https://your-node-ip:9090" "$YELLOW"
    print_message "Grafana:    https://your-node-ip:3000" "$YELLOW"
    print_message "Default Grafana login:" "$YELLOW"
    print_message "Username: admin" "$YELLOW"
    print_message "Password: admin" "$YELLOW"
    print_message "\nIMPORTANT: Please change the default password after first login!" "$RED"
    print_message "\nMonitoring Security:" "$YELLOW"
    print_message "- HTTPS enabled for all endpoints" "$YELLOW"
    print_message "- Self-signed certificates generated" "$YELLOW"
    print_message "- Default ports: 9090 (Prometheus), 3000 (Grafana)" "$YELLOW"
    print_message "- Ensure to configure firewall rules appropriately" "$YELLOW"
}

# Helper function for version checking
check_avalanchego_version() {
    local min_version="$1"
    VERSION_RESPONSE=$(curl -s -X POST --data '{
        "jsonrpc":"2.0",
        "id"     :1,
        "method" :"info.getNodeVersion"
    }' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info)
    
    if ! echo "$VERSION_RESPONSE" | grep -q "$min_version"; then
        print_message "Operation requires AvalancheGo version $min_version or higher" "$RED"
        return 1
    }
    return 0
}

# Helper function for BLS key operations
manage_bls_key_file() {
    local operation="$1"
    local source="$2"
    local target="$3"
    
    case $operation in
        "backup")
            cp "$source" "$target.$(date +%Y%m%d_%H%M%S).backup" || {
                print_message "Failed to backup BLS key" "$RED"
                return 1
            }
            ;;
        "replace")
            mv "$source" "$target" || {
                print_message "Failed to replace BLS key" "$RED"
                return 1
            }
            chmod 600 "$target"
            chown avalanche:avalanche "$target"
            ;;
    esac
    return 0
}

# Helper function for key verification
verify_key_pair() {
    local current_key="$1"
    local new_key="$2"
    
    if [ "$current_key" == "$new_key" ]; then
        print_message "Keys are identical. No action needed." "$GREEN"
        return 1
    }
    
    print_message "Current key: $current_key" "$YELLOW"
    print_message "New key: $new_key" "$YELLOW"
    read -p "Proceed with key operation? [y/n]: " confirm
    if [ "$confirm" != "y" ]; then
        print_message "Operation cancelled" "$YELLOW"
        return 1
    }
    return 0
}

# Consolidated BLS key management function
manage_bls_keys() {
    print_message "\nBLS Key Management" "$GREEN"
    echo "----------------------------------------"
    echo "Select operation:"
    echo "1) Upgrade/Rotate BLS Key"
    echo "2) Backup BLS Keys"
    echo "3) Generate New BLS Key"
    echo "4) Verify BLS Key Status"
    read -p "Enter choice (1-4): " bls_choice

    case $bls_choice in
        1)
            handle_bls_key_upgrade
            ;;
        2)
            backup_bls_keys
            ;;
        3)
            generate_new_bls_key
            ;;
        4)
            verify_bls_status
            ;;
        *)
            print_message "Invalid choice" "$RED"
            return 1
            ;;
    esac
}

# Consolidated function for BLS key upgrade/rotation
handle_bls_key_upgrade() {
    print_message "Starting BLS key operation..." "$YELLOW"
    
    # Check prerequisites
    if ! systemctl is-active --quiet avalanchego; then
        print_message "Node must be running" "$RED"
        return 1
    }
    
    if ! check_avalanchego_version "1.10."; then
        return 1
    }
    
    # Backup current key
    manage_bls_key_file "backup" "/home/avalanche/.avalanchego/staking/signer.key" "/home/avalanche/.avalanchego/staking/signer.key" || return 1
    
    # Generate new key if needed
    read -p "Generate new key? [y/n]: " gen_new
    if [ "$gen_new" == "y" ]; then
        avalanchego --generate-bls-key=/home/avalanche/.avalanchego/staking/signer.key.new || {
            print_message "Failed to generate new BLS key" "$RED"
            return 1
        }
        NEW_KEY_PATH="/home/avalanche/.avalanchego/staking/signer.key.new"
    else
        NEW_KEY_PATH="/home/avalanche/.avalanchego/staking/signer.key"
    fi
    
    # Get keys for comparison
    CURRENT_KEY=$(cat /home/avalanche/.avalanchego/staking/signer.key)
    NEW_KEY=$(cat $NEW_KEY_PATH)
    
    # Verify and proceed
    if ! verify_key_pair "$CURRENT_KEY" "$NEW_KEY"; then
        [ "$gen_new" == "y" ] && rm $NEW_KEY_PATH
        return 1
    fi
    
    # Perform upgrade
    if [ "$gen_new" == "y" ]; then
        manage_bls_key_file "replace" "$NEW_KEY_PATH" "/home/avalanche/.avalanchego/staking/signer.key" || return 1
    fi
    
    # Update registration
    UPGRADE_RESPONSE=$(curl -s -X POST -H 'Content-Type: application/json' --data "{
        \"jsonrpc\": \"2.0\",
        \"id\": 1,
        \"method\": \"platform.upgradeBLSKey\",
        \"params\": {
            \"oldKey\": \"$CURRENT_KEY\",
            \"newKey\": \"$NEW_KEY\"
        }
    }" http://localhost:9650/ext/bc/P)
    
    if echo "$UPGRADE_RESPONSE" | grep -q "error"; then
        print_message "Failed to update BLS key registration" "$RED"
        print_message "Error: $UPGRADE_RESPONSE" "$RED"
        return 1
    fi
    
    systemctl restart avalanchego
    print_message "BLS key operation completed successfully" "$GREEN"
    return 0
}

# Function to analyze existing service configuration
analyze_service_config() {
    local service_file="/etc/systemd/system/avalanchego.service"
    local config_found=false
    local rpc_access="private"
    local state_sync="on"
    local node_type="validator"
    
    if [ -f "$service_file" ]; then
        # Extract existing configuration from service file
        local exec_line=$(grep "^ExecStart=" "$service_file")
        
        # Determine node type based on configuration
        if echo "$exec_line" | grep -q "index-enabled=true"; then
            if echo "$exec_line" | grep -q "state-sync-disabled=true"; then
                node_type="archive"
            else
                node_type="api"
            fi
        fi
        
        # Determine RPC access
        if echo "$exec_line" | grep -q "http.addr=0.0.0.0"; then
            rpc_access="public"
        fi
        
        # Check state sync
        if echo "$exec_line" | grep -q "state-sync-disabled=true"; then
            state_sync="off"
        fi
        
        config_found=true
    fi
    
    echo "NODE_TYPE=$node_type"
    echo "RPC_ACCESS=$rpc_access"
    echo "STATE_SYNC=$state_sync"
    echo "CONFIG_FOUND=$config_found"
}

# Function to check monitoring prerequisites
check_monitoring_prerequisites() {
    print_message "Checking monitoring prerequisites..." "$YELLOW"
    
    # Check for existing monitoring installations
    if systemctl is-active --quiet prometheus || systemctl is-active --quiet grafana-server || systemctl is-active --quiet node_exporter; then
        print_message "Warning: Existing monitoring services detected" "$RED"
        read -p "Would you like to remove existing installations? [y/n]: " remove_existing
        if [ "$remove_existing" == "y" ]; then
            systemctl stop prometheus grafana-server node_exporter 2>/dev/null
            systemctl disable prometheus grafana-server node_exporter 2>/dev/null
            apt-get remove -y prometheus grafana prometheus-node-exporter 2>/dev/null
            apt-get autoremove -y 2>/dev/null
        else
            print_message "Please remove existing monitoring installations first" "$RED"
            exit 1
        fi
    fi
    
    # Check available disk space
    available_space=$(df -BG /var | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt 100 ]; then
        print_message "Warning: Less than 100GB available space for monitoring" "$RED"
        read -p "Continue anyway? [y/n]: " continue_install
        if [ "$continue_install" != "y" ]; then
            exit 1
        fi
    fi
    
    # Check memory
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 4 ]; then
        print_message "Warning: Less than 4GB RAM available" "$RED"
        read -p "Continue anyway? [y/n]: " continue_install
        if [ "$continue_install" != "y" ]; then
            exit 1
        fi
    fi

    print_message "Prerequisite checks completed successfully" "$GREEN"
    return 0
}

# Function to configure monitoring security
configure_monitoring_security() {
    print_message "Configuring monitoring security..." "$YELLOW"
    
    # Create directories if they don't exist
    mkdir -p /etc/prometheus /etc/grafana
    
    # Generate self-signed certificates
    openssl req -x509 -newkey rsa:4096 -keyout /etc/prometheus/prometheus.key \
        -out /etc/prometheus/prometheus.crt -days 365 -nodes -subj "/CN=prometheus" || {
        print_message "Failed to generate Prometheus certificates" "$RED"
        return 1
    }
        
    openssl req -x509 -newkey rsa:4096 -keyout /etc/grafana/grafana.key \
        -out /etc/grafana/grafana.crt -days 365 -nodes -subj "/CN=grafana" || {
        print_message "Failed to generate Grafana certificates" "$RED"
        return 1
    }

    # Update Prometheus config for TLS
    cat >> /etc/prometheus/prometheus.yml << EOF
tls_server_config:
  cert_file: /etc/prometheus/prometheus.crt
  key_file: /etc/prometheus/prometheus.key
EOF

    # Configure Grafana TLS
    sed -i 's/;protocol = http/protocol = https/' /etc/grafana/grafana.ini
    sed -i 's/;cert_file =/cert_file = \/etc\/grafana\/grafana.crt/' /etc/grafana/grafana.ini
    sed -i 's/;cert_key =/cert_key = \/etc\/grafana\/grafana.key/' /etc/grafana/grafana.ini

    # Set proper permissions
    chown -R prometheus:prometheus /etc/prometheus
    chown -R grafana:grafana /etc/grafana
    chmod 600 /etc/prometheus/prometheus.key /etc/grafana/grafana.key
    
    return 0
}

# Function to check performance baseline
check_performance_baseline() {
    print_message "Checking system performance baseline..." "$YELLOW"
    
    # Install fio if not present
    if ! command -v fio &> /dev/null; then
        apt-get install -y fio || {
            print_message "Failed to install fio for disk performance testing" "$RED"
            return 1
        }
    }
    
    # Check disk performance
    print_message "Testing disk performance..." "$YELLOW"
    if ! fio --name=randwrite --ioengine=libaio --rw=randwrite --bs=4k --numjobs=1 \
        --size=4g --iodepth=32 --runtime=10 --group_reporting | grep -q "IOPS.*>10000"; then
        print_message "Warning: Storage performance below recommended specifications" "$RED"
        print_message "Minimum 10,000 IOPS recommended for optimal performance" "$YELLOW"
        read -p "Continue anyway? [y/n]: " continue_install
        if [ "$continue_install" != "y" ]; then
            return 1
        fi
    fi
    
    # Check network performance
    print_message "Testing network latency..." "$YELLOW"
    if ! ping -c 4 8.8.8.8 | grep -q "time<100"; then
        print_message "Warning: Network latency above recommended threshold" "$RED"
        print_message "Maximum recommended latency is 100ms" "$YELLOW"
        read -p "Continue anyway? [y/n]: " continue_install
        if [ "$continue_install" != "y" ]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to verify backup
verify_backup() {
    local backup_dir="$1"
    print_message "Verifying backup integrity..." "$YELLOW"
    
    # Check backup directory exists
    if [ ! -d "$backup_dir" ]; then
        print_message "Backup directory not found: $backup_dir" "$RED"
        return 1
    }
    
    # Check staking files
    if [ -d "$backup_dir/staking" ]; then
        for file in staker.key staker.crt signer.key; do
            if [ ! -f "$backup_dir/staking/$file" ]; then
                print_message "Missing critical file: $file" "$RED"
                return 1
            fi
            
            # Check file permissions
            if [ "$(stat -c %a $backup_dir/staking/$file)" != "600" ]; then
                print_message "Warning: Incorrect permissions on $file" "$YELLOW"
                chmod 600 "$backup_dir/staking/$file" || {
                    print_message "Failed to set correct permissions on $file" "$RED"
                    return 1
                }
            fi
        done
    else
        print_message "Warning: No staking files found in backup" "$YELLOW"
    fi
    
    # Verify database backup if exists
    if [ -f "$backup_dir/db_backup.tar.gz" ]; then
        print_message "Verifying database backup archive..." "$YELLOW"
        if ! tar tf "$backup_dir/db_backup.tar.gz" &>/dev/null; then
            print_message "Database backup archive is corrupted" "$RED"
            return 1
        fi
        
        # Check archive size
        backup_size=$(du -m "$backup_dir/db_backup.tar.gz" | cut -f1)
        if [ "$backup_size" -lt 100 ]; then
            print_message "Warning: Database backup seems unusually small ($backup_size MB)" "$YELLOW"
            read -p "Continue anyway? [y/n]: " continue_verify
            if [ "$continue_verify" != "y" ]; then
                return 1
            fi
        fi
    elif [ -d "$backup_dir/db" ]; then
        print_message "Verifying direct database copy..." "$YELLOW"
        if [ ! -d "$backup_dir/db/db-1" ]; then
            print_message "Database directory structure appears invalid" "$RED"
            return 1
        fi
    fi
    
    print_message "Backup verification completed successfully" "$GREEN"
    return 0
}

# Function to perform GitHub backup
perform_github_backup() {
    print_message "\nGitHub Repository Backup" "$GREEN"
    echo "----------------------------------------"
    
    # Check for config file
    CONFIG_FILE="/home/avalanche/.avalanchego/github_backup.conf"
    if [ ! -f "$CONFIG_FILE" ]; then
        print_message "GitHub backup not configured. Running first-time setup..." "$YELLOW"
        setup_github_backup
        return
    }
    
    # Load configuration
    source "$CONFIG_FILE"
    
    # Verify token validity
    if ! curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user" | grep -q "login"; then
        print_message "GitHub token invalid or expired" "$RED"
        return 1
    }
    
    # Create timestamped backup directory
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR=$(mktemp -d)
    
    print_message "Creating backup..." "$YELLOW"
    
    # Check disk space
    available_space=$(df -BM "$BACKUP_DIR" | awk 'NR==2 {print $4}' | sed 's/M//')
    if [ "$available_space" -lt 1000 ]; then
        print_message "Insufficient disk space for backup" "$RED"
        rm -rf "$BACKUP_DIR"
        return 1
    }
    
    # Copy staking files with verification
    for file in staker.key staker.crt signer.key; do
        if [ ! -f "/home/avalanche/.avalanchego/staking/$file" ]; then
            print_message "Missing critical file: $file" "$RED"
            rm -rf "$BACKUP_DIR"
            return 1
        }
        cp "/home/avalanche/.avalanchego/staking/$file" "$BACKUP_DIR/" || {
            print_message "Failed to copy $file" "$RED"
            rm -rf "$BACKUP_DIR"
            return 1
        }
        # Verify copy
        if ! cmp -s "/home/avalanche/.avalanchego/staking/$file" "$BACKUP_DIR/$file"; then
            print_message "File verification failed for $file" "$RED"
            rm -rf "$BACKUP_DIR"
            return 1
        }
    }
    
    # Clone repository with timeout
    timeout 60 git clone "https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git" repo || {
        print_message "Failed to clone repository (timeout or error)" "$RED"
        rm -rf "$BACKUP_DIR"
        return 1
    }
    
    # Manage backup retention
    cd repo || return 1
    backup_count=$(ls -1 backups/ 2>/dev/null | wc -l)
    if [ "$backup_count" -gt 10 ]; then
        print_message "Cleaning old backups..." "$YELLOW"
        cd backups && ls -t | tail -n +11 | xargs rm -rf
        cd ..
    fi
    
    # Move files to repo
    mkdir -p "backups/$TIMESTAMP"
    mv "$BACKUP_DIR"/* "backups/$TIMESTAMP/" || {
        print_message "Failed to move backup files" "$RED"
        rm -rf "$BACKUP_DIR"
        return 1
    }
    
    # Add metadata file
    cat > "backups/$TIMESTAMP/backup_info.json" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "node_version": "$(avalanchego --version 2>/dev/null || echo 'unknown')",
    "backup_type": "full",
    "files": [
        "staker.key",
        "staker.crt",
        "signer.key"
    ]
}
EOF
    
    # Commit and push with retry
    git add .
    git -c "user.name=Avalanche Node" -c "user.email=$GITHUB_EMAIL" commit -m "Backup $TIMESTAMP" || {
        print_message "Failed to commit changes" "$RED"
        rm -rf "$BACKUP_DIR"
        return 1
    }
    
    for i in {1..3}; do
        if git push; then
            break
        else
            if [ $i -eq 3 ]; then
                print_message "Failed to push to repository after 3 attempts" "$RED"
                rm -rf "$BACKUP_DIR"
                return 1
            fi
            print_message "Push attempt $i failed, retrying..." "$YELLOW"
            sleep 5
        fi
    done
    
    # Verify backup
    if ! git ls-remote --heads origin main | grep -q main; then
        print_message "Failed to verify backup in repository" "$RED"
        rm -rf "$BACKUP_DIR"
        return 1
    }
    
    # Cleanup
    cd
    rm -rf "$BACKUP_DIR"
    
    print_message "Backup completed successfully" "$GREEN"
    print_message "Backup location: $GITHUB_REPO/backups/$TIMESTAMP" "$YELLOW"
    return 0
}

# Function to setup GitHub backup
setup_github_backup() {
    print_message "\nGitHub Backup Configuration" "$GREEN"
    echo "----------------------------------------"
    
    # Install required packages
    apt-get update
    apt-get install -y git || {
        print_message "Failed to install required packages" "$RED"
        return 1
    }
    
    # Get GitHub configuration
    read -p "Enter GitHub repository (format: username/repo): " GITHUB_REPO
    read -p "Enter GitHub Personal Access Token: " GITHUB_TOKEN
    read -p "Enter GitHub email for commits: " GITHUB_EMAIL
    
    # Save configuration
    cat > "$CONFIG_FILE" << EOF
GITHUB_REPO="$GITHUB_REPO"
GITHUB_TOKEN="$GITHUB_TOKEN"
GITHUB_EMAIL="$GITHUB_EMAIL"
EOF
    
    chmod 600 "$CONFIG_FILE"
    
    # Test configuration
    print_message "Testing GitHub access..." "$YELLOW"
    if ! curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPO" | grep -q "private"; then
        print_message "Failed to access repository. Please verify your token and repository name" "$RED"
        rm "$CONFIG_FILE"
        return 1
    fi
    
    print_message "GitHub backup configuration completed successfully" "$GREEN"
    print_message "\nImportant:" "$YELLOW"
    print_message "1. Keep your GitHub token secure" "$YELLOW"
    print_message "2. Ensure repository remains private" "$YELLOW"
    
    # Ask about automated backups
    read -p "Setup automated daily backups? [y/n]: " setup_cron
    if [ "$setup_cron" = "y" ]; then
        (crontab -l 2>/dev/null; echo "0 0 * * * $(pwd)/avalanche-deploy.sh --github-backup") | crontab - || {
            print_message "Failed to setup cron job" "$RED"
            return 1
        }
        print_message "Automated daily backups configured" "$GREEN"
    fi
    
    return 0
}

# Function to restore from GitHub
restore_from_github() {
    print_message "\nRestore from GitHub Backup" "$GREEN"
    echo "----------------------------------------"
    
    # Check for config file
    if [ ! -f "$CONFIG_FILE" ]; then
        print_message "GitHub backup not configured. Please configure backup first." "$RED"
        return 1
    }
    
    # Load configuration
    source "$CONFIG_FILE"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || return 1
    
    # Clone repository
    git clone "https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git" . || {
        print_message "Failed to clone repository" "$RED"
        rm -rf "$TEMP_DIR"
        return 1
    }
    
    # List available backups
    print_message "\nAvailable backups:" "$GREEN"
    ls -lt backups | grep '^d' | awk '{print $9}'
    
    # Select backup
    read -p "Enter backup timestamp to restore: " BACKUP_TIMESTAMP
    if [ ! -d "backups/$BACKUP_TIMESTAMP" ]; then
        print_message "Invalid backup timestamp" "$RED"
        rm -rf "$TEMP_DIR"
        return 1
    }
    
    # Stop node
    systemctl stop avalanchego
    
    # Backup current files
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    mkdir -p "/home/avalanche/.avalanchego/staking/backup_$BACKUP_TIMESTAMP"
    cp /home/avalanche/.avalanchego/staking/{staker.key,staker.crt,signer.key} \
       "/home/avalanche/.avalanchego/staking/backup_$BACKUP_TIMESTAMP/" 2>/dev/null
    
    # Restore files
    cd "backups/$BACKUP_TIMESTAMP" || return 1
    cp {staker.key,staker.crt,signer.key} /home/avalanche/.avalanchego/staking/ || {
        print_message "Failed to restore files" "$RED"
        rm -rf "$TEMP_DIR"
        systemctl start avalanchego
        return 1
    }
    
    # Set permissions
    chown -R avalanche:avalanche /home/avalanche/.avalanchego/staking
    chmod 600 /home/avalanche/.avalanchego/staking/{staker.key,staker.crt,signer.key}
    
    # Start node
    systemctl start avalanchego
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    print_message "Restore completed successfully" "$GREEN"
    print_message "Previous files backed up to: /home/avalanche/.avalanchego/staking/backup_$BACKUP_TIMESTAMP" "$YELLOW"
    
    return 0
}

# Update backup menu
backup_menu() {
    print_message "\nBackup Operations" "$GREEN"
    echo "----------------------------------------"
    echo "1) Local backup"
    echo "2) Remote backup (using scp)"
    echo "3) Configure GitHub backup"
    echo "4) Perform GitHub backup"
    echo "5) Restore from GitHub backup"
    echo "6) Return to main menu"
    
    read -p "Select option (1-6): " backup_choice
    
    case $backup_choice in
        1)
            perform_backup
            ;;
        2)
            perform_remote_backup
            ;;
        3)
            setup_github_backup
            ;;
        4)
            perform_github_backup
            ;;
        5)
            restore_from_github
            ;;
        6)
            return 0
            ;;
        *)
            print_message "Invalid choice" "$RED"
            return 1
            ;;
    esac
}

# Add command line option for automated backups
if [ "$1" = "--github-backup" ]; then
    perform_github_backup
    exit $?
fi 