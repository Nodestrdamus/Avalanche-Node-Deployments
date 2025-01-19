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
GOVERSION="1.22.8"  # Updated to latest recommended version
USER="avax"
HOME_DIR="/home/$USER"
AVALANCHE_DIR="$HOME_DIR/.avalanchego"
CONFIG_DIR="$AVALANCHE_DIR/configs"
CONFIG_FILE="$CONFIG_DIR/node.json"
BACKUP_DIR="$HOME_DIR/avalanche-backup"
CHAIN_DATA_DIR="$AVALANCHE_DIR/db"
MIN_CPU_CORES=8
MIN_RAM_GB=16
MIN_STORAGE_GB=1024

# Function to print colored output
print_message() {
    echo -e "${2}${1}${NC}"
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

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message "Please run as root (sudo)" "$RED"
        exit 1
    fi
}

# Check and install dependencies
install_dependencies() {
    print_message "Checking and installing dependencies..." "$YELLOW"
    apt-get update
    apt-get install -y git curl build-essential gcc g++ make

    # Install/upgrade gcc
    if ! command -v gcc &> /dev/null; then
        apt-get install -y gcc
    fi

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

# Create avalanche user and directories
setup_user() {
    if ! id "$USER" &>/dev/null; then
        useradd -m -s /bin/bash "$USER"
    fi
    
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$CHAIN_DATA_DIR"
    chown -R "$USER:$USER" "$HOME_DIR"
}

# Install or upgrade AvalancheGo
install_avalanchego() {
    print_message "Installing/Upgrading AvalancheGo..." "$YELLOW"
    su - "$USER" -c "
        cd $HOME_DIR
        if [ ! -d avalanchego ]; then
            git clone https://github.com/ava-labs/avalanchego.git
        fi
        cd avalanchego
        git fetch
        git checkout master
        git pull
        ./scripts/build.sh
    "
}

# Configure node based on type
configure_node() {
    local node_type=$1
    local network_id=$2
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
    "public-ip-resolution-service": "opendns",
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
    "public-ip-resolution-service": "opendns",
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
    "public-ip-resolution-service": "opendns",
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
ExecStart=$HOME_DIR/avalanchego/build/avalanchego --config-file=$CONFIG_FILE
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable avalanchego
    systemctl start avalanchego
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
        rm -rf "$AVALANCHE_DIR"
        tar -xzf "$BACKUP_DIR/$backup_file" -C "$HOME_DIR"
        chown -R "$USER:$USER" "$AVALANCHE_DIR"
        systemctl start avalanchego
        print_message "Restore completed" "$GREEN"
    else
        print_message "Backup file not found" "$RED"
    fi
}

# Select network
select_network() {
    echo "Select network:"
    echo "1) Mainnet"
    echo "2) Fuji (Testnet)"
    read -p "Enter choice [1-2]: " network_choice

    case $network_choice in
        1) echo "1";;  # mainnet
        2) echo "fuji";;  # fuji testnet
        *) print_message "Invalid choice" "$RED"; exit 1;;
    esac
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
            1|2|3)
                check_root
                check_system_requirements
                install_dependencies
                setup_user
                install_avalanchego
                network_id=$(select_network)
                case $choice in
                    1) configure_node "validator" "$network_id";;
                    2) configure_node "historical" "$network_id";;
                    3) configure_node "api" "$network_id";;
                esac
                setup_service "$network_id"
                print_message "Installation/Upgrade completed successfully!" "$GREEN"
                ;;
            4)
                check_root
                check_system_requirements
                install_dependencies
                setup_user
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