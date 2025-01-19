#!/bin/bash

# Avalanche Node Installation and Configuration Script
# Copyright (c) 2024 Rise & Shine Management. All Rights Reserved.
# This script is proprietary software of Rise & Shine Management.
# Unauthorized copying, modification, distribution, or use is strictly prohibited.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
GOARCH=$(uname -m)
AVALANCHEGO_VERSION="latest"
NODE_TYPE=""
CHAIN_CONFIG_DIR="$HOME/.avalanchego/configs/chains"
AVALANCHEGO_DIR="$HOME/avalanchego"
SERVICE_FILE="/etc/systemd/system/avalanchego.service"

print_banner() {
    echo -e "${GREEN}"
    echo "==============================================="
    echo "     Avalanche Node Installation Script        "
    echo "==============================================="
    echo -e "${NC}"
}

check_dependencies() {
    local deps=(curl wget systemctl)
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            echo -e "${RED}Error: Required dependency '$dep' is not installed.${NC}"
            exit 1
        fi
    done
}

select_node_type() {
    echo -e "${YELLOW}Please select node type:${NC}"
    echo "1) Validator Node (State Sync ON, Private RPC)"
    echo "2) Historical Node"
    echo "3) API Node"
    echo "4) Manual Configuration"
    read -p "Enter selection (1-4): " selection

    case $selection in
        1) NODE_TYPE="validator";;
        2) NODE_TYPE="historical";;
        3) NODE_TYPE="api";;
        4) NODE_TYPE="manual";;
        *) echo -e "${RED}Invalid selection${NC}"; exit 1;;
    esac
}

install_avalanchego() {
    echo -e "${GREEN}Installing AvalancheGo...${NC}"
    
    # Get latest version if not specified
    if [ "$AVALANCHEGO_VERSION" = "latest" ]; then
        AVALANCHEGO_VERSION=$(curl -s https://api.github.com/repos/ava-labs/avalanchego/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
    fi
    
    mkdir -p $AVALANCHEGO_DIR
    cd $AVALANCHEGO_DIR
    
    wget -N https://github.com/ava-labs/avalanchego/releases/download/${AVALANCHEGO_VERSION}/avalanchego-linux-${GOARCH}-${AVALANCHEGO_VERSION}.tar.gz
    tar xvf avalanchego-linux-${GOARCH}-${AVALANCHEGO_VERSION}.tar.gz
    rm avalanchego-linux-${GOARCH}-${AVALANCHEGO_VERSION}.tar.gz
    mv avalanchego-${AVALANCHEGO_VERSION}/* .
    rm -rf avalanchego-${AVALANCHEGO_VERSION}
}

configure_node() {
    mkdir -p $HOME/.avalanchego/configs
    
    case $NODE_TYPE in
        "validator")
            cat > $HOME/.avalanchego/configs/config.json <<EOF
{
    "network-id": "mainnet",
    "state-sync-enabled": true,
    "http-host": "127.0.0.1",
    "api-admin-enabled": false,
    "api-ipcs-enabled": false,
    "index-enabled": false
}
EOF
            ;;
        "historical")
            cat > $HOME/.avalanchego/configs/config.json <<EOF
{
    "network-id": "mainnet",
    "state-sync-enabled": false,
    "pruning-enabled": false,
    "api-admin-enabled": true,
    "index-enabled": true
}
EOF
            ;;
        "api")
            cat > $HOME/.avalanchego/configs/config.json <<EOF
{
    "network-id": "mainnet",
    "state-sync-enabled": true,
    "http-host": "0.0.0.0",
    "api-admin-enabled": true,
    "index-enabled": true
}
EOF
            ;;
        "manual")
            echo -e "${YELLOW}Using default config. Please modify $HOME/.avalanchego/configs/config.json manually.${NC}"
            cat > $HOME/.avalanchego/configs/config.json <<EOF
{
    "network-id": "mainnet",
    "state-sync-enabled": false
}
EOF
            ;;
    esac
}

setup_service() {
    echo -e "${GREEN}Setting up AvalancheGo as a system service...${NC}"
    
    cat > /tmp/avalanchego.service <<EOF
[Unit]
Description=AvalancheGo systemd service
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$AVALANCHEGO_DIR/avalanchego --config-file=$HOME/.avalanchego/configs/config.json
Restart=always
RestartSec=1
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/avalanchego.service $SERVICE_FILE
    sudo systemctl daemon-reload
    sudo systemctl enable avalanchego
    sudo systemctl start avalanchego
}

backup_node() {
    local backup_dir="$HOME/avalanche-backup"
    mkdir -p $backup_dir
    
    if systemctl is-active --quiet avalanchego; then
        sudo systemctl stop avalanchego
    fi
    
    tar -czf "$backup_dir/avalanche-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C $HOME .avalanchego
    
    echo -e "${GREEN}Backup created in $backup_dir${NC}"
}

main() {
    print_banner
    check_dependencies
    select_node_type
    
    # Backup existing installation if present
    if [ -d "$HOME/.avalanchego" ]; then
        echo -e "${YELLOW}Existing installation detected. Creating backup...${NC}"
        backup_node
    fi
    
    install_avalanchego
    configure_node
    setup_service
    
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "Node type: $NODE_TYPE"
    echo -e "Version: $AVALANCHEGO_VERSION"
    echo -e "Config location: $HOME/.avalanchego/configs/config.json"
    echo -e "Service status: $(systemctl is-active avalanchego)"
}

main 