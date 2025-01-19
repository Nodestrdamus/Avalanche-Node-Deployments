#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Check Ubuntu version
version=$(lsb_release -rs)
if [[ "$version" != "20.04" && "$version" != "24.04" ]]; then
    echo -e "${RED}This script only supports Ubuntu 20.04 and 24.04${NC}"
    exit 1
fi

# Function to check if AvalancheGo is already installed
check_existing_installation() {
    if systemctl is-active --quiet avalanchego; then
        echo -e "${YELLOW}AvalancheGo is already installed and running.${NC}"
        echo -e "Would you like to:"
        echo "1) Upgrade existing installation"
        echo "2) Remove existing installation and perform fresh install"
        echo "3) Exit"
        read -p "Enter selection (1-3): " upgrade_choice
        
        case $upgrade_choice in
            1) upgrade_avalanchego;;
            2) remove_existing_installation;;
            3) exit 0;;
            *) echo -e "${RED}Invalid selection${NC}"; exit 1;;
        esac
    fi
}

# Function to upgrade AvalancheGo
upgrade_avalanchego() {
    echo -e "${GREEN}Upgrading AvalancheGo...${NC}"
    systemctl stop avalanchego
    cd /opt/avalanchego/avalanchego || exit 1
    git pull
    ./scripts/build.sh
    systemctl start avalanchego
    echo -e "${GREEN}Upgrade complete!${NC}"
    exit 0
}

# Function to remove existing installation
remove_existing_installation() {
    echo -e "${YELLOW}Removing existing installation...${NC}"
    systemctl stop avalanchego
    systemctl disable avalanchego
    rm -f /etc/systemd/system/avalanchego.service
    rm -rf /opt/avalanchego
    systemctl daemon-reload
    echo -e "${GREEN}Existing installation removed.${NC}"
}

# Function to install dependencies
install_dependencies() {
    echo -e "${GREEN}Installing dependencies...${NC}"
    apt-get update
    apt-get install -y git curl wget make gcc g++ jq systemd
}

# Function to create AvalancheGo directory
setup_avalanchego_dir() {
    mkdir -p /opt/avalanchego
    cd /opt/avalanchego || exit 1
}

# Function to clone and build AvalancheGo
install_avalanchego() {
    echo -e "${GREEN}Cloning AvalancheGo repository...${NC}"
    git clone https://github.com/ava-labs/avalanchego.git
    cd avalanchego || exit 1
    echo -e "${GREEN}Building AvalancheGo...${NC}"
    ./scripts/build.sh
}

# Function to create systemd service
create_systemd_service() {
    local node_type=$1
    local network=$2
    
    # Create service file
    cat > /etc/systemd/system/avalanchego.service << EOF
[Unit]
Description=AvalancheGo systemd service
After=network.target

[Service]
Type=simple
User=avalanche
ExecStart=/opt/avalanchego/avalanchego/build/avalanchego --network-id=$network $NODE_CONFIG
Restart=always
RestartSec=1
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOF

    # Create avalanche user if it doesn't exist
    id -u avalanche &>/dev/null || useradd -rs /bin/false avalanche

    # Set permissions
    chown -R avalanche:avalanche /opt/avalanchego

    # Enable and start service
    systemctl daemon-reload
    systemctl enable avalanchego
    systemctl start avalanchego
}

# Main installation process
echo -e "${GREEN}Welcome to AvalancheGo Node Installation Script${NC}"

# Check for existing installation
check_existing_installation

# Install dependencies
install_dependencies

# Select node type
echo -e "${YELLOW}Please select node type:${NC}"
echo "1) Validator Node"
echo "2) Historical Node"
echo "3) API Node"
read -p "Enter selection (1-3): " node_type

case $node_type in
    1) NODE_CONFIG="--http-host=127.0.0.1";;
    2) NODE_CONFIG="--http-host=127.0.0.1 --index-enabled=true";;
    3) NODE_CONFIG="--http-host=0.0.0.0 --index-enabled=true --api-admin-enabled=true --api-ipcs-enabled=true";;
    *) echo -e "${RED}Invalid selection${NC}"; exit 1;;
esac

# Select IP type
echo -e "${YELLOW}Select IP type:${NC}"
echo "1) Residential (Dynamic IP)"
echo "2) Cloud/Datacenter (Static IP)"
read -p "Enter selection (1-2): " ip_type

case $ip_type in
    1) NODE_CONFIG="$NODE_CONFIG --dynamic-public-ip=opendns";;
    2) NODE_CONFIG="$NODE_CONFIG --public-ip=$(curl -s ifconfig.me)";;
    *) echo -e "${RED}Invalid selection${NC}"; exit 1;;
esac

# Select network
echo -e "${YELLOW}Select network:${NC}"
echo "1) Mainnet"
echo "2) Fuji (Testnet)"
read -p "Enter selection (1-2): " network

case $network in
    1) NETWORK_ID="1";;
    2) NETWORK_ID="5";;
    *) echo -e "${RED}Invalid selection${NC}"; exit 1;;
esac

# Setup and install
setup_avalanchego_dir
install_avalanchego
create_systemd_service "$node_type" "$NETWORK_ID"

# Wait for node to start
echo -e "${YELLOW}Waiting for node to start...${NC}"
sleep 10

# Get NodeID
NODE_ID=$(curl -s -X POST --data '{"jsonrpc":"2.0","id":1,"method":"info.getNodeID"}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info | jq -r '.result.nodeID')

# Display information
echo -e "\n${GREEN}Installation Complete!${NC}"
echo -e "${YELLOW}Your NodeID is:${NC} $NODE_ID"
echo -e "\n${YELLOW}Node Management Commands:${NC}"
echo "Start node:   sudo systemctl start avalanchego"
echo "Stop node:    sudo systemctl stop avalanchego"
echo "Check status: sudo systemctl status avalanchego"
echo "View logs:    sudo journalctl -u avalanchego -f"

# Display upgrade information
echo -e "\n${YELLOW}To upgrade your node in the future, run this script again and select the upgrade option.${NC}" 