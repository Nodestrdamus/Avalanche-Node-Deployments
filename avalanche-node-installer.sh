#!/bin/bash

set -e

VERSION="1.0.0"
GOVERSION="1.21.7"
AVALANCHE_REPO="https://github.com/ava-labs/avalanchego.git"
GOPATH="$HOME/go"
AVALANCHEGO_PATH="$GOPATH/src/github.com/ava-labs/avalanchego"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
NETWORK_ID=""
HOME_DIR="$HOME/.avalanchego"
UPDATE_MODE=false

print_banner() {
    echo "=================================================="
    echo "Avalanche Node Installer v${VERSION}"
    echo "=================================================="
}

print_step() {
    echo -e "\n${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}"
}

get_current_avalanchego_version() {
    if [ -f "$AVALANCHEGO_PATH/build/avalanchego" ]; then
        CURRENT_VERSION=$($AVALANCHEGO_PATH/build/avalanchego --version | grep -oP 'avalanche/\K[0-9]+\.[0-9]+\.[0-9]+')
        echo "$CURRENT_VERSION"
    else
        echo ""
    fi
}

get_latest_avalanchego_version() {
    print_step "Getting latest AvalancheGo version..."
    AVALANCHEGO_VERSION=$(curl -s https://api.github.com/repos/ava-labs/avalanchego/releases/latest | grep -oP '"tag_name": "\K[^"]+' | sed 's/^v//')
    if [ -z "$AVALANCHEGO_VERSION" ]; then
        print_error "Failed to get latest AvalancheGo version"
        exit 1
    fi
    echo "✓ Latest AvalancheGo version: v${AVALANCHEGO_VERSION}"
}

backup_node_data() {
    print_step "Backing up node data..."
    BACKUP_DIR="$HOME_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup configuration
    if [ -f "$HOME_DIR/configs/node.json" ]; then
        cp -r "$HOME_DIR/configs" "$BACKUP_DIR/"
    fi
    
    # Backup staking keys
    if [ -d "$HOME_DIR/staking" ]; then
        cp -r "$HOME_DIR/staking" "$BACKUP_DIR/"
    fi
    
    # Backup chain configs if they exist
    if [ -d "$HOME_DIR/chains" ]; then
        cp -r "$HOME_DIR/chains" "$BACKUP_DIR/"
    fi
    
    echo "✓ Backup created at: $BACKUP_DIR"
}

check_for_updates() {
    print_step "Checking for updates..."
    CURRENT_VERSION=$(get_current_avalanchego_version)
    
    if [ -z "$CURRENT_VERSION" ]; then
        print_warning "AvalancheGo not currently installed"
        return
    fi
    
    get_latest_avalanchego_version
    
    if [ "$CURRENT_VERSION" = "$AVALANCHEGO_VERSION" ]; then
        echo "✓ You are running the latest version (v${CURRENT_VERSION})"
        exit 0
    else
        echo "New version available: v${AVALANCHEGO_VERSION} (current: v${CURRENT_VERSION})"
        read -p "Would you like to update? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            UPDATE_MODE=true
        else
            exit 0
        fi
    fi
}

update_avalanchego() {
    print_step "Performing in-place upgrade of AvalancheGo..."
    
    # Create backup
    backup_node_data
    
    # Stop the service
    print_step "Stopping AvalancheGo service..."
    sudo systemctl stop avalanchego
    
    # Wait for service to fully stop
    sleep 5
    
    # Update the code
    cd "$AVALANCHEGO_PATH"
    print_step "Fetching latest code..."
    git fetch --all
    git checkout "v$AVALANCHEGO_VERSION"
    
    print_step "Building AvalancheGo..."
    ./scripts/build.sh
    
    # Update systemd service if needed
    setup_systemd_service
    
    print_step "Starting AvalancheGo service..."
    sudo systemctl daemon-reload
    sudo systemctl start avalanchego
    
    # Wait for service to start
    sleep 5
    
    # Check if service is running
    if systemctl is-active --quiet avalanchego; then
        print_step "Update completed successfully!"
        echo "New version: v${AVALANCHEGO_VERSION}"
        echo "Backup location: $BACKUP_DIR"
        echo "✓ Node is running"
    else
        print_error "Node failed to start after update. Rolling back..."
        rollback_update
    fi
}

rollback_update() {
    print_step "Rolling back to previous version..."
    
    # Stop the service
    sudo systemctl stop avalanchego
    
    # Restore from backup
    if [ -d "$BACKUP_DIR" ]; then
        cp -r "$BACKUP_DIR/configs"/* "$HOME_DIR/configs/"
        cp -r "$BACKUP_DIR/staking"/* "$HOME_DIR/staking/"
        if [ -d "$BACKUP_DIR/chains" ]; then
            cp -r "$BACKUP_DIR/chains"/* "$HOME_DIR/chains/"
        fi
    fi
    
    # Checkout previous version
    cd "$AVALANCHEGO_PATH"
    git checkout "v$CURRENT_VERSION"
    ./scripts/build.sh
    
    # Start service
    sudo systemctl start avalanchego
    
    print_error "Update failed. Rolled back to v${CURRENT_VERSION}"
    echo "Please check the logs for more information: sudo journalctl -u avalanchego -n 100 --no-pager"
    exit 1
}

check_requirements() {
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi

    # Check Ubuntu version
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu"; then
        print_error "This installer requires Ubuntu 20.04 or 24.04"
        exit 1
    fi

    UBUNTU_VERSION=$(lsb_release -rs)
    case $UBUNTU_VERSION in
        20.04|24.04)
            echo "✓ Ubuntu ${UBUNTU_VERSION} detected"
            ;;
        *)
            print_error "This installer requires Ubuntu 20.04 or 24.04 (detected: ${UBUNTU_VERSION})"
            exit 1
            ;;
    esac
}

install_dependencies() {
    print_step "Installing dependencies..."
    
    # Update package list
    sudo apt-get update
    
    # Install required packages
    sudo apt-get install -y \
        git \
        curl \
        build-essential \
        pkg-config \
        libssl-dev \
        libuv1-dev \
        gcc \
        make \
        tar \
        wget \
        jq \
        ufw \
        lsb-release

    # Install Go if not installed
    if ! command -v go &> /dev/null; then
        print_step "Installing Go ${GOVERSION}..."
        wget "https://golang.org/dl/go${GOVERSION}.linux-amd64.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go${GOVERSION}.linux-amd64.tar.gz"
        rm "go${GOVERSION}.linux-amd64.tar.gz"
        
        # Set up Go environment
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
        echo 'export GOPATH=$HOME/go' >> ~/.profile
        echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
        source ~/.profile
    fi
}

setup_avalanchego() {
    print_step "Setting up AvalancheGo from source..."
    
    # Create GOPATH directory structure
    mkdir -p $GOPATH/src/github.com/ava-labs
    cd $GOPATH/src/github.com/ava-labs
    
    # Clone AvalancheGo
    if [ -d "avalanchego" ]; then
        print_warning "AvalancheGo directory already exists. Removing..."
        rm -rf avalanchego
    fi
    git clone $AVALANCHE_REPO
    cd avalanchego
    
    # Get latest version
    get_latest_avalanchego_version
    git checkout "v$AVALANCHEGO_VERSION"
    
    # Build AvalancheGo
    ./scripts/build.sh

    # Create required directories
    mkdir -p "$HOME_DIR"/{db,configs,staking}
    chmod 700 "$HOME_DIR/staking"

    # Generate config
    generate_config

    # Setup systemd service
    setup_systemd_service
}

generate_config() {
    print_step "Generating node configuration..."
    
    CONFIG_FILE="$HOME_DIR/configs/node.json"
    
    # Base configuration following Avalanche docs
    cat > "$CONFIG_FILE" << EOL
{
    "network-id": "${NETWORK_ID}",
    "http-host": "",
    "http-port": 9650,
    "staking-port": 9651,
    "db-dir": "${HOME_DIR}/db",
    "log-level": "info",
    "log-display-level": "info",
    "log-dir": "${HOME_DIR}/logs",
    "api-admin-enabled": false,
    "api-ipcs-enabled": false,
    "index-enabled": false,
    "api-keystore-enabled": false,
    "api-metrics-enabled": true,
    "bootstrap-retry-enabled": true,
    "bootstrap-retry-warm-up": "5m",
    "health-check-frequency": "2m",
    "health-check-averager-halflife": "10s",
    "network-minimum-timeout": "5s",
    "network-initial-timeout": "5s"
}
EOL
}

setup_systemd_service() {
    print_step "Setting up systemd service..."
    
    sudo tee /etc/systemd/system/avalanchego.service > /dev/null << EOL
[Unit]
Description=AvalancheGo Node
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$USER
ExecStart=$GOPATH/src/github.com/ava-labs/avalanchego/build/avalanchego --config-file=${HOME_DIR}/configs/node.json
Restart=always
RestartSec=1
LimitNOFILE=32768
TimeoutStopSec=300

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable avalanchego
}

configure_firewall() {
    print_step "Configuring firewall..."
    
    sudo ufw allow 22/tcp comment 'SSH'
    sudo ufw allow 9651/tcp comment 'Avalanche P2P'
    sudo ufw allow 9650/tcp comment 'Avalanche API'
    sudo ufw --force enable
}

check_bootstrap_status() {
    local chain=$1
    local result=$(curl -s -X POST --data "{
        \"jsonrpc\":\"2.0\",
        \"id\":1,
        \"method\":\"info.isBootstrapped\",
        \"params\":{
            \"chain\":\"$chain\"
        }
    }" -H 'content-type:application/json;' 127.0.0.1:9650/ext/info)
    
    if [[ $result == *"true"* ]]; then
        echo "✓ $chain-Chain is bootstrapped"
        return 0
    else
        echo "⧖ $chain-Chain is still bootstrapping"
        return 1
    fi
}

start_node() {
    print_step "Starting AvalancheGo node..."
    sudo systemctl start avalanchego
    
    # Wait for node to start
    sleep 5
    
    # Check if node is running
    if systemctl is-active --quiet avalanchego; then
        echo "✓ Node started successfully"
        print_step "Checking initial bootstrap status..."
        check_bootstrap_status "P"
        check_bootstrap_status "X"
        check_bootstrap_status "C"
        echo "Note: Full bootstrapping may take several days"
    else
        print_error "Failed to start node. Check logs with: sudo journalctl -u avalanchego -f"
        exit 1
    fi
}

main() {
    print_banner
    
    # Check for --update flag
    if [ "$1" = "--update" ]; then
        check_for_updates
        if [ "$UPDATE_MODE" = true ]; then
            update_avalanchego
            exit 0
        fi
    fi
    
    check_requirements
    install_dependencies
    
    # Set up network ID
    print_step "Select network:"
    echo "1) Mainnet"
    echo "2) Fuji (Testnet)"
    
    while true; do
        read -p "Enter your choice [1-2]: " choice
        case $choice in
            1) NETWORK_ID="mainnet"; break;;
            2) NETWORK_ID="fuji"; break;;
            *) echo "Invalid choice. Please enter 1 or 2.";;
        esac
    done
    
    setup_avalanchego
    configure_firewall
    start_node
    
    print_step "Installation completed successfully!"
    echo "=================================================="
    echo "Network: $NETWORK_ID"
    echo "=================================================="
    echo "Useful commands:"
    echo "- Check node status: sudo systemctl status avalanchego"
    echo "- View logs: sudo journalctl -u avalanchego -f"
    echo "- Stop node: sudo systemctl stop avalanchego"
    echo "- Start node: sudo systemctl start avalanchego"
    echo "- Check bootstrap status: curl -X POST --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"info.isBootstrapped\",\"params\":{\"chain\":\"X\"}}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info"
    echo "=================================================="
    echo "RPC Endpoints when bootstrapped:"
    echo "- P-Chain: localhost:9650/ext/bc/P"
    echo "- X-Chain: localhost:9650/ext/bc/X"
    echo "- C-Chain: localhost:9650/ext/bc/C/rpc"
    echo "=================================================="
}

main "$@" 