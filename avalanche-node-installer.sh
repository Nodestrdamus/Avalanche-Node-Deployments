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

get_latest_avalanchego_version() {
    print_step "Getting latest AvalancheGo version..."
    AVALANCHEGO_VERSION=$(curl -s https://api.github.com/repos/ava-labs/avalanchego/releases/latest | grep -oP '"tag_name": "\K[^"]+' | sed 's/^v//')
    if [ -z "$AVALANCHEGO_VERSION" ]; then
        print_error "Failed to get latest AvalancheGo version"
        exit 1
    fi
    echo "✓ Latest AvalancheGo version: v${AVALANCHEGO_VERSION}"
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
    mkdir -p "$HOME_DIR"/{db,configs,staking,logs}
    chmod 700 "$HOME_DIR/staking"

    # Generate staking keys for validator nodes
    if [ "$NODE_TYPE" = "$VALIDATOR_NODE" ]; then
        if [ ! -f "$HOME_DIR/staking/staker.key" ]; then
            print_step "Generating staking keys..."
            "$GOPATH/src/github.com/ava-labs/avalanchego/build/avalanchego" --staking-tls-cert-file="$HOME_DIR/staking/staker.crt" --staking-tls-key-file="$HOME_DIR/staking/staker.key" || true
            if [ -f "$HOME_DIR/staking/staker.key" ]; then
                echo "✓ Staking keys generated successfully"
                chmod 600 "$HOME_DIR/staking/staker.key"
                chmod 600 "$HOME_DIR/staking/staker.crt"
            else
                print_error "Failed to generate staking keys"
                exit 1
            fi
        else
            print_warning "Staking keys already exist, skipping generation"
        fi
    fi

    # Generate config
    generate_config

    # Setup systemd service
    setup_systemd_service
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