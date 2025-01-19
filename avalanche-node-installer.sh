#!/bin/bash

set -e

VERSION="1.0.0"
GOVERSION="1.21.7"
AVALANCHE_REPO="https://github.com/ava-labs/avalanchego.git"
HOME_DIR="$HOME/.avalanchego"
AVALANCHEGO_PATH="$HOME/avalanchego"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
NETWORK_ID=""
NODE_TYPE=""
IP_TYPE=""

# Node type constants
VALIDATOR_NODE="validator"
HISTORICAL_NODE="historical"
API_NODE="api"

# IP type constants
RESIDENTIAL_IP="residential"
STATIC_IP="static"

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

check_requirements() {
    print_step "Checking system requirements..."
    
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
        lsb-release \
        htop

    # Install Go if not installed or if version doesn't match
    local current_go_version=""
    if command -v go &> /dev/null; then
        current_go_version=$(go version | awk '{print $3}' | sed 's/go//')
    fi
    
    if [ "$current_go_version" != "$GOVERSION" ]; then
        print_step "Installing Go ${GOVERSION}..."
        wget "https://golang.org/dl/go${GOVERSION}.linux-amd64.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go${GOVERSION}.linux-amd64.tar.gz"
        rm "go${GOVERSION}.linux-amd64.tar.gz"
        
        # Set up Go environment
        if ! grep -q "GOPATH" ~/.profile; then
            echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
            echo 'export GOPATH=$HOME/go' >> ~/.profile
            echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
        fi
        source ~/.profile
    fi
}

setup_avalanchego() {
    print_step "Setting up AvalancheGo from source..."
    
    cd $HOME
    
    # Backup existing installation if it exists
    if [ -d "avalanchego" ]; then
        print_warning "Existing AvalancheGo installation found. Creating backup..."
        timestamp=$(date +%Y%m%d_%H%M%S)
        
        # Backup staking keys if they exist
        if [ -f "$HOME_DIR/staking/staker.key" ] && [ -f "$HOME_DIR/staking/staker.crt" ]; then
            print_step "Backing up existing staking keys..."
            mkdir -p "avalanchego_backup_${timestamp}/staking"
            cp "$HOME_DIR/staking/staker.key" "avalanchego_backup_${timestamp}/staking/"
            cp "$HOME_DIR/staking/staker.crt" "avalanchego_backup_${timestamp}/staking/"
            chmod 600 "avalanchego_backup_${timestamp}/staking/staker.key"
            chmod 600 "avalanchego_backup_${timestamp}/staking/staker.crt"
            echo "✓ Staking keys backed up"
        fi
        
        mv avalanchego "avalanchego_backup_$timestamp"
    fi

    # Clone and build AvalancheGo
    git clone $AVALANCHE_REPO
    cd avalanchego
    git checkout $(curl -s https://api.github.com/repos/ava-labs/avalanchego/releases/latest | jq -r '.tag_name')
    ./scripts/build.sh

    # Create required directories and set permissions
    mkdir -p "$HOME_DIR"/{db,configs,staking,logs}
    chmod 700 "$HOME_DIR"
    chmod 700 "$HOME_DIR/staking"
    chmod 755 "$HOME_DIR/configs"
    chmod 700 "$HOME_DIR/db"
    chmod 755 "$HOME_DIR/logs"
    
    # Ensure user owns all directories
    sudo chown -R $USER:$USER "$HOME_DIR"
    sudo chown -R $USER:$USER "$AVALANCHEGO_PATH"

    # For validator nodes, check for existing keys before generating new ones
    if [ "$NODE_TYPE" = "$VALIDATOR_NODE" ]; then
        # Check for backup keys first
        if [ -f "avalanchego_backup_${timestamp}/staking/staker.key" ] && [ -f "avalanchego_backup_${timestamp}/staking/staker.crt" ]; then
            print_step "Restoring existing staking keys..."
            cp "avalanchego_backup_${timestamp}/staking/staker.key" "$HOME_DIR/staking/"
            cp "avalanchego_backup_${timestamp}/staking/staker.crt" "$HOME_DIR/staking/"
            chmod 600 "$HOME_DIR/staking/staker.key"
            chmod 600 "$HOME_DIR/staking/staker.crt"
            echo "✓ Staking keys restored"
        else
            generate_staking_keys
        fi
    fi

    generate_config
    setup_systemd_service
}

generate_staking_keys() {
    if [ ! -f "$HOME_DIR/staking/staker.key" ]; then
        print_step "Generating staking keys..."
        
        "$AVALANCHEGO_PATH/build/avalanchego" \
            --staking-tls-cert-file="$HOME_DIR/staking/staker.crt" \
            --staking-tls-key-file="$HOME_DIR/staking/staker.key" || true
        
        if [ -f "$HOME_DIR/staking/staker.key" ] && [ -f "$HOME_DIR/staking/staker.crt" ]; then
            chmod 600 "$HOME_DIR/staking/staker.key"
            chmod 600 "$HOME_DIR/staking/staker.crt"
            echo "✓ Staking keys generated successfully"
        else
            print_error "Failed to generate staking keys"
            exit 1
        fi
    else
        print_warning "Staking keys already exist, skipping generation"
    fi
}

generate_config() {
    print_step "Generating node configuration..."
    
    CONFIG_FILE="$HOME_DIR/configs/node.json"
    
    # Base configuration common to all node types
    local base_config='{
        "network-id": "'${NETWORK_ID}'",
        "http-host": "127.0.0.1",
        "http-port": 9650,
        "staking-port": 9651,
        "db-dir": "'${HOME_DIR}'/db",
        "log-level": "info",
        "log-display-level": "info",
        "log-dir": "'${HOME_DIR}'/logs",
        "api-admin-enabled": false,
        "api-ipcs-enabled": false,
        "api-keystore-enabled": false,
        "api-metrics-enabled": true,
        "bootstrap-retry-enabled": true,
        "bootstrap-retry-warm-up": "5m",
        "health-check-frequency": "2m",
        "health-check-averger-halflife": "10s",
        "network-minimum-timeout": "5s",
        "network-initial-timeout": "5s"'

    # Node type specific configurations
    case $NODE_TYPE in
        $VALIDATOR_NODE)
            # For validator nodes, configure based on IP type
            local dynamic_nat_config=""
            if [ "$IP_TYPE" = "$RESIDENTIAL_IP" ]; then
                dynamic_nat_config=',
                    "dynamic-public-ip": "opendns",
                    "dynamic-update-duration": "5m"'
            fi
            
            local node_config="$base_config,
                \"snow-sample-size\": 20,
                \"snow-quorum-size\": 15,
                \"staking-enabled\": true,
                \"staking-tls-cert-file\": \"${HOME_DIR}/staking/staker.crt\",
                \"staking-tls-key-file\": \"${HOME_DIR}/staking/staker.key\",
                \"api-admin-enabled\": false,
                \"api-ipcs-enabled\": false,
                \"index-enabled\": false,
                \"pruning-enabled\": true,
                \"state-sync-enabled\": true${dynamic_nat_config}
            }"
            ;;
        $HISTORICAL_NODE)
            local node_config="$base_config,
                \"snow-sample-size\": 20,
                \"snow-quorum-size\": 15,
                \"staking-enabled\": false,
                \"api-admin-enabled\": true,
                \"api-ipcs-enabled\": true,
                \"index-enabled\": true,
                \"pruning-enabled\": false,
                \"state-sync-enabled\": false
            }"
            ;;
        $API_NODE)
            local node_config="$base_config,
                \"snow-sample-size\": 20,
                \"snow-quorum-size\": 15,
                \"staking-enabled\": false,
                \"api-admin-enabled\": true,
                \"api-ipcs-enabled\": false,
                \"index-enabled\": true,
                \"pruning-enabled\": true,
                \"state-sync-enabled\": true
            }"
            ;;
    esac

    echo "$node_config" | jq '.' > "$CONFIG_FILE"
    echo "✓ Configuration generated for ${NODE_TYPE} node"
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
Group=$USER
WorkingDirectory=$AVALANCHEGO_PATH
ExecStart=$AVALANCHEGO_PATH/build/avalanchego --config-file=${HOME_DIR}/configs/node.json
Restart=always
RestartSec=1
LimitNOFILE=32768
TimeoutStopSec=300
StandardOutput=append:${HOME_DIR}/logs/avalanchego.log
StandardError=append:${HOME_DIR}/logs/avalanchego.err

[Install]
WantedBy=multi-user.target
EOL

    sudo chmod 644 /etc/systemd/system/avalanchego.service
    sudo systemctl daemon-reload
    sudo systemctl enable avalanchego
}

configure_firewall() {
    print_step "Configuring firewall..."
    
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow 22/tcp comment 'SSH'
    sudo ufw allow 9651/tcp comment 'Avalanche P2P'
    
    case $NODE_TYPE in
        $VALIDATOR_NODE)
            # Validator nodes should be more restrictive
            ;;
        $HISTORICAL_NODE|$API_NODE)
            sudo ufw allow 9650/tcp comment 'Avalanche API'
            ;;
    esac
    
    sudo ufw --force enable
}

start_node() {
    print_step "Starting AvalancheGo node..."
    sudo systemctl start avalanchego
    
    # Wait for node to start
    sleep 5
    
    # Check if node is running
    if systemctl is-active --quiet avalanchego; then
        echo "✓ Node started successfully"
        
        # Get NodeID
        sleep 2
        NODE_ID=$(curl -s -X POST --data '{"jsonrpc": "2.0","method":"info.getNodeID","params":{},"id":1}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info | jq -r '.result.nodeID')
        
        print_step "Node Information and Next Steps"
        echo "=================================================="
        echo "Your node has started and is now bootstrapping!"
        echo "This process will take several days to complete."
        echo ""
        if [ ! -z "$NODE_ID" ]; then
            echo "Your NodeID: $NODE_ID"
            if [ "$NODE_TYPE" = "$VALIDATOR_NODE" ]; then
                echo "Track your validator's progress at:"
                echo "https://avascan.info/staking/validator/$NODE_ID"
                echo ""
            fi
        fi
        echo "IMPORTANT: Monitor your node's progress using:"
        echo "------------------------------------------------"
        echo "1. View real-time logs (recommended):"
        echo "   sudo journalctl -u avalanchego -f"
        echo ""
        echo "2. Check service status:"
        echo "   sudo systemctl status avalanchego"
        echo ""
        echo "3. Check bootstrap progress:"
        echo "   curl -X POST --data '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"info.isBootstrapped\",\"params\":{\"chain\":\"P\"}}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info"
        echo "   (Replace P with X or C for other chains)"
        echo ""
        echo "4. Monitor system resources:"
        echo "   htop"
        echo "=================================================="
        echo "Your node is now running! Please save your NodeID."
        echo "Follow the monitoring instructions above to track progress."
        echo "=================================================="
    else
        print_error "Failed to start node. Check logs with: sudo journalctl -u avalanchego -f"
        exit 1
    fi
}

main() {
    print_banner
    
    check_requirements
    install_dependencies
    
    # Select node type
    print_step "Select node type:"
    echo "1) Validator Node"
    echo "2) Historical RPC Node"
    echo "3) API Node"
    
    while true; do
        read -p "Enter your choice [1-3]: " choice
        case $choice in
            1) NODE_TYPE=$VALIDATOR_NODE; break;;
            2) NODE_TYPE=$HISTORICAL_NODE; break;;
            3) NODE_TYPE=$API_NODE; break;;
            *) echo "Invalid choice. Please enter 1, 2, or 3.";;
        esac
    done
    
    # For validator nodes, ask about IP type
    if [ "$NODE_TYPE" = "$VALIDATOR_NODE" ]; then
        print_step "Select IP type:"
        echo "1) Residential IP (Dynamic)"
        echo "2) Static IP"
        
        while true; do
            read -p "Enter your choice [1-2]: " choice
            case $choice in
                1) IP_TYPE=$RESIDENTIAL_IP; break;;
                2) IP_TYPE=$STATIC_IP; break;;
                *) echo "Invalid choice. Please enter 1 or 2.";;
            esac
        done
    fi
    
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
}

main "$@" 