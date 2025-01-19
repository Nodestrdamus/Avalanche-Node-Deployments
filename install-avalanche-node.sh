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
    apt-get install -y git curl wget make gcc g++ jq systemd build-essential

    # Verify installation with detailed output
    echo -e "${YELLOW}Verifying installed dependencies...${NC}"
    for cmd in git curl wget make gcc g++ jq systemctl; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Failed to install $cmd${NC}"
            echo -e "${YELLOW}Attempting to fix installation...${NC}"
            apt-get install -y $cmd
            if ! command -v $cmd &> /dev/null; then
                echo -e "${RED}Could not install $cmd. Please install it manually.${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}$cmd installed successfully${NC}"
        fi
    done
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
    
    # Create avalanche user if it doesn't exist and set shell to /bin/bash for debugging
    id -u avalanche &>/dev/null || useradd -m -s /bin/bash avalanche

    # Create and set permissions for data directory with proper ownership
    mkdir -p /var/lib/avalanchego
    chown -R avalanche:avalanche /var/lib/avalanchego
    chmod 755 /var/lib/avalanchego

    # Ensure binary is executable and owned by avalanche user
    chmod 755 /opt/avalanchego/avalanchego/build/avalanchego
    chown -R avalanche:avalanche /opt/avalanchego

    # Debug: Test binary execution as avalanche user
    echo -e "${YELLOW}Testing binary execution...${NC}"
    su - avalanche -c "/opt/avalanchego/avalanchego/build/avalanchego --version"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Binary execution test failed. Check permissions and binary integrity.${NC}"
        exit 1
    fi
    
    # Create service file with environment setup and absolute paths
    cat > /etc/systemd/system/avalanchego.service << EOF
[Unit]
Description=AvalancheGo systemd service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=avalanche
Group=avalanche
WorkingDirectory=/var/lib/avalanchego
Environment=HOME=/var/lib/avalanchego
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/opt/avalanchego/avalanchego/build/avalanchego \\
    --network-id=$network \\
    --db-dir=/var/lib/avalanchego/db \\
    --log-dir=/var/lib/avalanchego/logs \\
    --plugin-dir=/var/lib/avalanchego/plugins \\
    $NODE_CONFIG
Restart=always
RestartSec=1
TimeoutStopSec=300
LimitNOFILE=32768

# Hardening
ProtectSystem=full
PrivateTmp=true
NoNewPrivileges=true
PrivateDevices=true

[Install]
WantedBy=multi-user.target
EOF

    # Create required directories with proper permissions
    for dir in logs db plugins; do
        mkdir -p /var/lib/avalanchego/$dir
        chown avalanche:avalanche /var/lib/avalanchego/$dir
        chmod 755 /var/lib/avalanchego/$dir
    done

    # Debug: List permissions
    echo -e "${YELLOW}Checking directory permissions...${NC}"
    ls -la /var/lib/avalanchego/
    ls -la /opt/avalanchego/avalanchego/build/

    # Reload systemd and start service with debugging
    echo -e "${YELLOW}Reloading systemd daemon...${NC}"
    systemctl daemon-reload

    echo -e "${YELLOW}Enabling avalanchego service...${NC}"
    systemctl enable avalanchego

    echo -e "${YELLOW}Starting avalanchego service...${NC}"
    systemctl start avalanchego

    # Wait and check service status with detailed output
    sleep 5
    if ! systemctl is-active --quiet avalanchego; then
        echo -e "${RED}Service failed to start. Collecting debug information...${NC}"
        echo -e "\n${YELLOW}Service Status:${NC}"
        systemctl status avalanchego
        echo -e "\n${YELLOW}Last 50 Journal Entries:${NC}"
        journalctl -u avalanchego -n 50 --no-pager
        echo -e "\n${YELLOW}Binary Location and Permissions:${NC}"
        ls -l /opt/avalanchego/avalanchego/build/avalanchego
        echo -e "\n${YELLOW}Service Configuration:${NC}"
        cat /etc/systemd/system/avalanchego.service
        exit 1
    fi
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