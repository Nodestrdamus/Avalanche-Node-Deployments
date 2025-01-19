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
GOVERSION="1.20.10"
USER="avax"
HOME_DIR="/home/$USER"
AVALANCHE_DIR="$HOME_DIR/.avalanchego"
CONFIG_FILE="$AVALANCHE_DIR/configs/node.json"
BACKUP_DIR="$HOME_DIR/avalanche-backup"

# Function to print colored output
print_message() {
    echo -e "${2}${1}${NC}"
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
    apt-get install -y git curl build-essential

    # Install/upgrade gcc
    if ! command -v gcc &> /dev/null; then
        apt-get install -y gcc
    fi

    # Install/upgrade Go
    if ! command -v go &> /dev/null || [[ $(go version | awk '{print $3}' | sed 's/go//') != $GOVERSION ]]; then
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
    
    mkdir -p "$AVALANCHE_DIR/configs"
    mkdir -p "$BACKUP_DIR"
    chown -R "$USER:$USER" "$HOME_DIR"
}

# Install or upgrade AvalancheGo
install_avalanchego() {
    print_message "Installing/Upgrading AvalancheGo..." "$YELLOW"
    su - "$USER" -c "
        cd $HOME_DIR
        git clone https://github.com/ava-labs/avalanchego.git 2>/dev/null || (cd avalanchego && git pull)
        cd avalanchego
        ./scripts/build.sh
    "
}

# Configure node based on type
configure_node() {
    local node_type=$1
    local config="{}"

    case $node_type in
        "validator")
            config=$(cat <<EOF
{
    "state-sync-enabled": true,
    "http-host": "127.0.0.1",
    "api-admin-enabled": false,
    "api-ipcs-enabled": false,
    "index-enabled": false
}
EOF
)
            ;;
        "historical")
            config=$(cat <<EOF
{
    "state-sync-enabled": false,
    "api-admin-enabled": true,
    "index-enabled": true,
    "pruning-enabled": false
}
EOF
)
            ;;
        "api")
            config=$(cat <<EOF
{
    "state-sync-enabled": true,
    "http-host": "0.0.0.0",
    "api-admin-enabled": true,
    "api-ipcs-enabled": true,
    "index-enabled": true
}
EOF
)
            ;;
    esac

    echo "$config" > "$CONFIG_FILE"
    chown "$USER:$USER" "$CONFIG_FILE"
}

# Setup systemd service
setup_service() {
    cat > /etc/systemd/system/avalanchego.service <<EOF
[Unit]
Description=AvalancheGo systemd service
StartLimitIntervalSec=0

[Service]
Type=simple
User=$USER
ExecStart=$HOME_DIR/avalanchego/build/avalanchego --config-file=$CONFIG_FILE
Restart=always
RestartSec=1

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
    tar -czf "$BACKUP_DIR/avalanche-backup-$(date +%Y%m%d).tar.gz" -C "$HOME_DIR" .avalanchego
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
        systemctl start avalanchego
        print_message "Restore completed" "$GREEN"
    else
        print_message "Backup file not found" "$RED"
    fi
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
        echo "7) Exit"
        
        read -p "Select an option: " choice

        case $choice in
            1|2|3)
                check_root
                install_dependencies
                setup_user
                install_avalanchego
                case $choice in
                    1) configure_node "validator";;
                    2) configure_node "historical";;
                    3) configure_node "api";;
                esac
                setup_service
                print_message "Installation/Upgrade completed successfully!" "$GREEN"
                ;;
            4)
                check_root
                install_dependencies
                setup_user
                install_avalanchego
                print_message "Manual installation completed. Please configure node.json manually." "$YELLOW"
                ;;
            5) backup_node;;
            6) restore_node;;
            7) exit 0;;
            *) print_message "Invalid option" "$RED";;
        esac
    done
}

# Start the script
main_menu 