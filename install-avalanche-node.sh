#!/bin/bash

# Avalanche Node Installation and Management Script
# Author: Nodestrdamus
# Repository: https://github.com/Nodestrdamus/Avalanche-Node-Deployments

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
GOVERSION="1.22.8"
USER="avax"
HOME_DIR="/home/$USER"
AVALANCHEGO_HOME="/home/AvalancheGo"
AVALANCHE_DATA_DIR="$AVALANCHEGO_HOME/.avalanchego"
CONFIG_DIR="$AVALANCHE_DATA_DIR/configs"
CONFIG_FILE="$CONFIG_DIR/node.json"
CHAIN_DATA_DIR="$AVALANCHE_DATA_DIR/db"
BACKUP_DIR="$AVALANCHEGO_HOME/backups"
LOG_DIR="$AVALANCHEGO_HOME/logs"
BIN_DIR="$AVALANCHEGO_HOME/bin"
SRC_DIR="$AVALANCHEGO_HOME/src"
MIN_CPU_CORES=8
MIN_RAM_GB=16
MIN_STORAGE_GB=1024

# Function to print colored output
print_message() {
    echo -e "${2}${1}${NC}"
}

# Create directory structure
create_directories() {
    print_message "Creating directory structure..." "$YELLOW"
    
    # Create main directories
    mkdir -p "$AVALANCHEGO_HOME"
    mkdir -p "$AVALANCHE_DATA_DIR"
    mkdir -p "$CONFIG_DIR/chains"
    mkdir -p "$CHAIN_DATA_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BIN_DIR"
    mkdir -p "$SRC_DIR"
    mkdir -p "/home/$USER/go"  # Create GOPATH directory
    
    # Set permissions
    chown -R "$USER:$USER" "$HOME_DIR"
    chown -R "$USER:$USER" "$AVALANCHEGO_HOME"
    chown -R "$USER:$USER" "/home/$USER/go"
    chmod 750 "$AVALANCHEGO_HOME"
    chmod 750 "$AVALANCHE_DATA_DIR"
    chmod 750 "$CONFIG_DIR"
    chmod 750 "$BACKUP_DIR"
    chmod 750 "$LOG_DIR"
    chmod 750 "$BIN_DIR"
    chmod 750 "$SRC_DIR"
    chmod -R 750 "/home/$USER/go"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message "Please run as root (sudo)" "$RED"
        exit 1
    fi
}

# Check system requirements
check_system_requirements() {
    print_message "Checking system requirements..." "$YELLOW"
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt "$MIN_CPU_CORES" ]; then
        print_message "Warning: Insufficient CPU cores. Recommended: $MIN_CPU_CORES, Found: $CPU_CORES" "$YELLOW"
    fi
    
    # Check RAM
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM_GB" -lt "$MIN_RAM_GB" ]; then
        print_message "Warning: Insufficient RAM. Recommended: ${MIN_RAM_GB}GB, Found: ${TOTAL_RAM_GB}GB" "$YELLOW"
    fi
    
    # Check Storage
    FREE_STORAGE_GB=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$FREE_STORAGE_GB" -lt "$MIN_STORAGE_GB" ]; then
        print_message "Warning: Insufficient free storage. Recommended: ${MIN_STORAGE_GB}GB, Found: ${FREE_STORAGE_GB}GB" "$YELLOW"
    fi
}

# Create avalanche user
setup_user() {
    print_message "Setting up Avalanche user..." "$YELLOW"
    if ! id "$USER" &>/dev/null; then
        useradd -m -s /bin/bash "$USER"
        # Set up environment for avax user
        echo 'export GOPATH=/home/avax/go' >> "/home/$USER/.profile"
        echo 'export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin' >> "/home/$USER/.profile"
        print_message "Created user: $USER" "$GREEN"
    fi
    
    # Ensure .profile is owned by avax user
    chown "$USER:$USER" "/home/$USER/.profile"
}

# Check and install dependencies
install_dependencies() {
    print_message "Checking and installing dependencies..." "$YELLOW"
    apt-get update
    apt-get install -y git curl build-essential gcc g++ make

    # Install/upgrade Go
    if ! command -v go &> /dev/null || [[ $(go version | awk '{print $3}' | sed 's/go//') != $GOVERSION ]]; then
        print_message "Installing Go version $GOVERSION..." "$YELLOW"
        wget "https://golang.org/dl/go${GOVERSION}.linux-amd64.tar.gz"
        rm -rf /usr/local/go
        tar -C /usr/local -xzf "go${GOVERSION}.linux-amd64.tar.gz"
        rm "go${GOVERSION}.linux-amd64.tar.gz"
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
        echo 'export GOPATH=$HOME/go' >> /etc/profile
        source /etc/profile
    fi
}

# Install or upgrade AvalancheGo
install_avalanchego() {
    print_message "\n=== Installing/Upgrading AvalancheGo ===" "$YELLOW"
    su - "$USER" -c "
        cd $SRC_DIR
        if [ ! -d avalanchego ]; then
            git clone https://github.com/ava-labs/avalanchego.git
        fi
        cd avalanchego
        git fetch
        git checkout master
        git pull
        ./scripts/build.sh
        cp build/avalanchego $BIN_DIR/
        chmod 750 $BIN_DIR/avalanchego
    "
    print_message "AvalancheGo installation completed successfully!" "$GREEN"
}

# Select network environment
select_network_environment() {
    print_message "\nNetwork Environment Setup:" "$YELLOW"
    echo -e "1) Residential Network (Dynamic IP)"
    echo -e "2) Cloud/Datacenter (Static IP)"
    echo -e "\nNote:"
    echo -e "- Residential: For nodes running on home/dynamic IP connections"
    echo -e "- Cloud/Datacenter: For nodes running with static IP addresses"
    echo -e ""
    
    local ip_type=""
    local public_ip=""
    
    while true; do
        read -p "Enter your choice [1-2]: " env_choice
        case $env_choice in
            1)
                print_message "Selected: Residential Network (Dynamic IP)" "$GREEN"
                ip_type="dynamic"
                break
                ;;
            2)
                print_message "Selected: Cloud/Datacenter (Static IP)" "$GREEN"
                ip_type="static"
                # Try to detect public IP
                public_ip=$(curl -s https://api.ipify.org)
                if [ ! -z "$public_ip" ]; then
                    echo -e "\nDetected public IP: $public_ip"
                    read -p "Is this your static IP? [y/n]: " confirm
                    if [[ $confirm != "y" && $confirm != "Y" ]]; then
                        read -p "Please enter your static IP: " public_ip
                    fi
                else
                    read -p "Please enter your static IP: " public_ip
                fi
                break
                ;;
            *)
                print_message "Invalid choice. Please enter 1 for Residential or 2 for Cloud/Datacenter" "$RED"
                ;;
        esac
    done
    
    echo "$ip_type:$public_ip"
}

# Configure node based on type
configure_node() {
    local node_type=$1
    local network_id=$2
    local network_env=$3
    local ip_type=${network_env%:*}
    local public_ip=${network_env#*:}
    local config="{}"

    case $node_type in
        "validator")
            config=$(cat <<EOF
{
    "network-id": "${network_id}",
    "state-sync-enabled": true,
    "http-host": "127.0.0.1",
    "api-admin-enabled": false,
    "api-ipcs-enabled": false,
    "index-enabled": false,
    "db-dir": "${CHAIN_DATA_DIR}",
    "log-level": "info",
    "public-ip-resolution-service": "$([ "$ip_type" = "dynamic" ] && echo "opendns" || echo "none")",
    $([ "$ip_type" = "static" ] && echo "\"public-ip\": \"$public_ip\",")
    "http-tls-enabled": false,
    "metrics-enabled": true,
    "chain-config-dir": "${CONFIG_DIR}/chains"
}
EOF
)
            ;;
        "historical")
            config=$(cat <<EOF
{
    "network-id": "${network_id}",
    "state-sync-enabled": false,
    "api-admin-enabled": true,
    "index-enabled": true,
    "db-dir": "${CHAIN_DATA_DIR}",
    "pruning-enabled": false,
    "log-level": "info",
    "public-ip-resolution-service": "$([ "$ip_type" = "dynamic" ] && echo "opendns" || echo "none")",
    $([ "$ip_type" = "static" ] && echo "\"public-ip\": \"$public_ip\",")
    "http-tls-enabled": false,
    "metrics-enabled": true,
    "chain-config-dir": "${CONFIG_DIR}/chains"
}
EOF
)
            ;;
        "api")
            config=$(cat <<EOF
{
    "network-id": "${network_id}",
    "state-sync-enabled": true,
    "http-host": "0.0.0.0",
    "api-admin-enabled": true,
    "api-ipcs-enabled": true,
    "index-enabled": true,
    "db-dir": "${CHAIN_DATA_DIR}",
    "log-level": "info",
    "public-ip-resolution-service": "$([ "$ip_type" = "dynamic" ] && echo "opendns" || echo "none")",
    $([ "$ip_type" = "static" ] && echo "\"public-ip\": \"$public_ip\",")
    "http-tls-enabled": false,
    "metrics-enabled": true,
    "chain-config-dir": "${CONFIG_DIR}/chains"
}
EOF
)
            ;;
    esac

    mkdir -p "${CONFIG_DIR}/chains"
    echo "$config" > "$CONFIG_FILE"
    chown -R "$USER:$USER" "$CONFIG_DIR"
}

# Setup systemd service
setup_service() {
    local network_id=$1
    
    # Create log files with proper permissions
    touch "$LOG_DIR/avalanchego.log"
    touch "$LOG_DIR/avalanchego.error.log"
    chown "$USER:$USER" "$LOG_DIR/avalanchego.log"
    chown "$USER:$USER" "$LOG_DIR/avalanchego.error.log"
    chmod 640 "$LOG_DIR/avalanchego.log"
    chmod 640 "$LOG_DIR/avalanchego.error.log"
    
    cat > /etc/systemd/system/avalanchego.service <<EOF
[Unit]
Description=AvalancheGo systemd service
StartLimitIntervalSec=0
After=network.target

[Service]
Type=simple
User=$USER
Restart=always
RestartSec=1
Environment=GOPATH=/home/avax/go
Environment=PATH=/usr/local/go/bin:/home/avax/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$BIN_DIR/avalanchego --config-file=$CONFIG_FILE
LimitNOFILE=32768
StandardOutput=append:$LOG_DIR/avalanchego.log
StandardError=append:$LOG_DIR/avalanchego.error.log
WorkingDirectory=$AVALANCHEGO_HOME

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable avalanchego
    systemctl start avalanchego
    
    # Give the service a moment to start
    sleep 5
    
    # Check if service started successfully
    if ! systemctl is-active --quiet avalanchego; then
        print_message "Warning: Service failed to start. Checking logs..." "$RED"
        journalctl -u avalanchego -n 50 --no-pager
        exit 1
    fi
}

# Backup node data
backup_node() {
    print_message "Creating backup..." "$YELLOW"
    systemctl stop avalanchego
    tar -czf "$BACKUP_DIR/avalanche-backup-$(date +%Y%m%d_%H%M%S).tar.gz" -C "$HOME_DIR" .avalanchego
    systemctl start avalanchego
    print_message "Backup completed" "$GREEN"
}

# Restore node data
restore_node() {
    print_message "Available backups:" "$YELLOW"
    ls -1 "$BACKUP_DIR"
    read -p "Enter backup file name to restore: " backup_file

    if [ -f "$BACKUP_DIR/$backup_file" ]; then
        systemctl stop avalanchego
        rm -rf "$AVALANCHE_DATA_DIR"
        tar -xzf "$BACKUP_DIR/$backup_file" -C "$HOME_DIR"
        chown -R "$USER:$USER" "$AVALANCHE_DATA_DIR"
        systemctl start avalanchego
        print_message "Restore completed" "$GREEN"
    else
        print_message "Backup file not found" "$RED"
    fi
}

# Select network
select_network() {
    print_message "\nSelect Network:" "$YELLOW"
    echo -e "1) Mainnet (Production Network)"
    echo -e "2) Fuji (Test Network)"
    echo -e "\nNote:"
    echo -e "- Mainnet is the production Avalanche network"
    echo -e "- Fuji is the test network for development and testing"
    echo -e ""
    while true; do
        read -p "Enter your choice [1-2]: " network_choice
        case $network_choice in
            1) 
                print_message "Selected: Mainnet" "$GREEN"
                echo "1"
                break
                ;;
            2)
                print_message "Selected: Fuji Testnet" "$GREEN"
                echo "fuji"
                break
                ;;
            *)
                print_message "Invalid choice. Please enter 1 for Mainnet or 2 for Fuji Testnet" "$RED"
                ;;
        esac
    done
}

# Monitor node status
monitor_node() {
    print_message "Checking node status..." "$YELLOW"
    systemctl status avalanchego
    
    # Check if node is bootstrapped
    curl -X POST --data '{
        "jsonrpc":"2.0",
        "id"     :1,
        "method" :"info.isBootstrapped",
        "params": {
            "chain":"X"
        }
    }' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info
}

# Display node information and management commands
display_node_info() {
    local node_type=$1
    local network_id=$2
    
    print_message "\n=== Node Installation Complete! ===" "$GREEN"
    
    print_message "\nNode ID:" "$YELLOW"
    # Give the service a moment to start and write logs
    sleep 5
    
    # Get NodeID from logs
    local nodeid=$(sudo journalctl -u avalanchego | grep "NodeID" | head -1 | cut -d ':' -f4 | tr -d ' ')
    
    if [ ! -z "$nodeid" ]; then
        print_message "Your Node ID is: $nodeid" "$GREEN"
    else
        print_message "\nTo get your NodeID, run this command:" "$YELLOW"
        echo "   sudo journalctl -u avalanchego | grep \"NodeID\""
    fi
    
    print_message "\n=== Node Management Commands ===" "$YELLOW"
    echo -e "\n1. Start/Stop/Restart Node:"
    echo "   sudo systemctl start avalanchego    # Start the node"
    echo "   sudo systemctl stop avalanchego     # Stop the node"
    echo "   sudo systemctl restart avalanchego  # Restart the node"
    
    echo -e "\n2. Check Node Status:"
    echo "   sudo systemctl status avalanchego   # View service status"
    
    echo -e "\n3. View Node Logs:"
    echo "   sudo journalctl -u avalanchego -f   # Follow logs in real-time"
    
    if [ "$node_type" = "validator" ]; then
        print_message "\n=== Validator Node Information ===" "$YELLOW"
        echo "1. Save your NodeID - You'll need it for staking"
        echo "2. Ensure your node is running: sudo systemctl status avalanchego"
        echo "3. Monitor logs: sudo journalctl -u avalanchego -f"
        echo "4. Visit https://wallet.avax.network/ to stake your AVAX"
    fi
    
    print_message "\nNeed help? Check the documentation at https://docs.avax.network/" "$YELLOW"
    
    # Prompt to save information
    echo -e "\nWould you like to save these instructions to a file? [y/n]"
    read -r save_info
    if [[ $save_info == "y" || $save_info == "Y" ]]; then
        local info_file="$HOME_DIR/node-info-$(date +%Y%m%d_%H%M%S).txt"
        display_node_info "$node_type" "$network_id" > "$info_file" 2>&1
        chown "$USER:$USER" "$info_file"
        print_message "Information saved to: $info_file" "$GREEN"
    fi
}

# Main installation function
install_node() {
    local node_type=$1
    
    # 1. Initial checks
    print_message "\n=== Phase 1: System Checks ===" "$YELLOW"
    check_root
    check_system_requirements
    
    # 2. Setup system
    print_message "\n=== Phase 2: System Setup ===" "$YELLOW"
    setup_user
    create_directories
    install_dependencies
    
    # 3. Install AvalancheGo
    print_message "\n=== Phase 3: AvalancheGo Installation ===" "$YELLOW"
    install_avalanchego
    
    # 4. Configure node
    print_message "\n=== Phase 4: Node Configuration ===" "$YELLOW"
    
    print_message "\n=== Network Selection ===" "$GREEN"
    print_message "Choose your network type:" "$YELLOW"
    echo -e "Option 1: Mainnet - Production Avalanche network"
    echo -e "Option 2: Fuji   - Test network for development"
    echo -e "\nThis choice determines which Avalanche network your node will connect to."
    network_id=$(select_network)
    
    print_message "\n=== Network Environment ===" "$GREEN"
    print_message "Choose your network environment:" "$YELLOW"
    echo -e "Option 1: Residential  - For home/dynamic IP setups"
    echo -e "Option 2: Datacenter   - For static IP deployments"
    echo -e "\nThis choice configures your node's network settings appropriately."
    network_env=$(select_network_environment)
    
    print_message "\nConfiguring node with selected options..." "$YELLOW"
    configure_node "$node_type" "$network_id" "$network_env"
    
    # 5. Setup service and start node
    print_message "\n=== Phase 5: Service Setup ===" "$YELLOW"
    setup_service "$network_id"
    
    # 6. Display node information
    print_message "\n=== Phase 6: Installation Complete ===" "$GREEN"
    display_node_info "$node_type" "$network_id"
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n${YELLOW}Avalanche Node Installation and Management${NC}"
        echo "1) Install/Upgrade Validator Node"
        echo "2) Install/Upgrade Historical Node"
        echo "3) Install/Upgrade API Node"
        echo "4) Manual Configuration"
        echo "5) Backup Node"
        echo "6) Restore Node"
        echo "7) Monitor Node Status"
        echo "8) Exit"
        
        read -p "Select an option: " choice

        case $choice in
            1) install_node "validator";;
            2) install_node "historical";;
            3) install_node "api";;
            4)
                check_root
                check_system_requirements
                setup_user
                create_directories
                install_dependencies
                install_avalanchego
                print_message "Manual installation completed. Please configure node.json manually." "$YELLOW"
                ;;
            5) backup_node;;
            6) restore_node;;
            7) monitor_node;;
            8) exit 0;;
            *) print_message "Invalid option" "$RED";;
        esac
    done
}

# Start the script
main_menu 