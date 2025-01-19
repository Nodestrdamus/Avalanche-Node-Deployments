#!/bin/bash

set -e

VERSION="1.0.0"
GOVERSION="1.21.7"
AVALANCHE_REPO="https://github.com/ava-labs/avalanchego.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration variables
NODE_TYPE=""
NETWORK_ID=""
IS_STATIC_IP=false
PUBLIC_IP=""
RPC_PUBLIC=false
STATE_SYNC_ENABLED=false
HOME_DIR="$HOME/.avalanchego"
UPGRADE_MODE=false

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
    print_step "Checking latest AvalancheGo version from official repository..."
    LATEST_VERSION=$(curl -s https://api.github.com/repos/ava-labs/avalanchego/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [ -z "$LATEST_VERSION" ]; then
        print_error "Failed to fetch latest AvalancheGo version from Avalanche repository"
        exit 1
    fi
    AVALANCHEGO_VERSION=${LATEST_VERSION#v}
    echo "Latest AvalancheGo version from Avalanche: $AVALANCHEGO_VERSION"
}

check_for_updates() {
    if [ -d "$HOME/avalanchego" ]; then
        cd "$HOME/avalanchego"
        # Ensure we're tracking the official repository
        git remote set-url origin $AVALANCHE_REPO 2>/dev/null || git remote add origin $AVALANCHE_REPO
        git fetch --all --tags
        CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "unknown")
        get_latest_avalanchego_version
        if [ "$CURRENT_VERSION" != "v$AVALANCHEGO_VERSION" ]; then
            print_warning "New version available from Avalanche: v$AVALANCHEGO_VERSION (current: $CURRENT_VERSION)"
            read -p "Would you like to upgrade? [y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                UPGRADE_MODE=true
                return 0
            fi
        else
            echo "AvalancheGo is up to date with official Avalanche release (v$AVALANCHEGO_VERSION)"
        fi
    fi
    return 1
}

upgrade_avalanchego() {
    print_step "Upgrading AvalancheGo to official version v$AVALANCHEGO_VERSION..."
    
    # Stop the service
    sudo systemctl stop avalanchego
    
    # Backup current version
    BACKUP_DIR="$HOME_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r "$HOME_DIR/configs" "$BACKUP_DIR/"
    if [ -d "$HOME_DIR/staking" ]; then
        cp -r "$HOME_DIR/staking" "$BACKUP_DIR/"
    fi
    
    # Update the code from official repository
    cd "$HOME/avalanchego"
    git fetch --all --tags
    git checkout "v$AVALANCHEGO_VERSION"
    
    # Rebuild using official build script
    ./scripts/build.sh
    
    # Update systemd service if needed
    setup_systemd_service
    
    # Restart the service
    sudo systemctl start avalanchego
    
    print_step "Upgrade to official Avalanche version completed successfully!"
    echo "Backup of previous configuration saved to: $BACKUP_DIR"
}

check_requirements() {
    print_step "Checking system requirements..."

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi

    # Check Ubuntu version
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 24.04"; then
        print_error "This installer requires Ubuntu 24.04.1"
        exit 1
    fi

    # Initialize requirements check status
    local requirements_met=true

    # Check CPU cores
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 8 ]; then
        requirements_met=false
        print_warning "Your system has less than the recommended 8 CPU cores (detected: ${CPU_CORES})"
        read -p "Do you want to continue anyway? [y/n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✓ CPU cores check passed (detected: ${CPU_CORES} cores)"
    fi

    # Check RAM
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 16 ]; then
        requirements_met=false
        print_warning "Your system has less than the recommended 16GB of RAM (detected: ${TOTAL_RAM}GB)"
        read -p "Do you want to continue anyway? [y/n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✓ RAM check passed (detected: ${TOTAL_RAM}GB)"
    fi

    # Check disk space
    DISK_SPACE=$(df -BG / | awk '/^\/dev/{print $4}' | tr -d 'G')
    if [ "$DISK_SPACE" -lt 1000 ]; then
        requirements_met=false
        print_warning "Your system has less than the recommended 1TB of free disk space (detected: ${DISK_SPACE}GB)"
        read -p "Do you want to continue anyway? [y/n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✓ Disk space check passed (detected: ${DISK_SPACE}GB free)"
    fi

    if [ "$requirements_met" = true ]; then
        print_step "All system requirements met! Proceeding with installation..."
    fi
}

install_dependencies() {
    print_step "Installing dependencies..."
    
    sudo apt-get update
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
        lsb-release

    # Install Go
    if ! command -v go &> /dev/null; then
        print_step "Installing Go ${GOVERSION}..."
        wget "https://golang.org/dl/go${GOVERSION}.linux-amd64.tar.gz"
        sudo rm -rf /usr/local/go
        sudo tar -C /usr/local -xzf "go${GOVERSION}.linux-amd64.tar.gz"
        rm "go${GOVERSION}.linux-amd64.tar.gz"
        
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
        echo 'export GOPATH=$HOME/go' >> ~/.profile
        echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
        source ~/.profile
    fi

    # Verify Go installation
    if ! command -v go &> /dev/null; then
        print_error "Failed to install Go"
        exit 1
    fi
}

get_node_type() {
    print_step "Select node type:"
    echo "1) Validator Node (for staking)"
    echo "2) Historical Node (full archive)"
    echo "3) API Node (RPC endpoint)"
    
    while true; do
        read -p "Enter your choice [1-3]: " choice
        case $choice in
            1) NODE_TYPE="validator"; break;;
            2) NODE_TYPE="historical"; break;;
            3) NODE_TYPE="api"; break;;
            *) echo "Invalid choice. Please enter 1, 2, or 3.";;
        esac
    done
}

get_network() {
    print_step "Select network:"
    echo "1) Mainnet"
    echo "2) Fuji (Testnet)"
    echo "3) Local"
    
    while true; do
        read -p "Enter your choice [1-3]: " choice
        case $choice in
            1) NETWORK_ID="mainnet"; break;;
            2) NETWORK_ID="fuji"; break;;
            3) NETWORK_ID="local"; break;;
            *) echo "Invalid choice. Please enter 1, 2, or 3.";;
        esac
    done
}

get_ip_config() {
    print_step "Network configuration:"
    echo "1) Residential network (dynamic IP)"
    echo "2) Cloud provider (static IP)"
    
    while true; do
        read -p "Enter your connection type [1,2]: " choice
        case $choice in
            1) IS_STATIC_IP=false; break;;
            2) IS_STATIC_IP=true; break;;
            *) echo "Invalid choice. Please enter 1 or 2.";;
        esac
    done

    if [ "$IS_STATIC_IP" = true ]; then
        PUBLIC_IP=$(curl -s https://api.ipify.org)
        echo "Detected public IP: $PUBLIC_IP"
        read -p "Is this correct? [y/n]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            read -p "Enter your public IP: " PUBLIC_IP
        fi
    fi
}

get_rpc_config() {
    if [ "$NODE_TYPE" == "validator" ]; then
        # Automatically set to private for validator nodes
        RPC_PUBLIC=false
        echo "RPC access automatically set to private for validator node"
    else
        print_step "RPC configuration:"
        read -p "Should RPC port be public (public) or private (private)? [public/private]: " rpc_choice
        if [[ $rpc_choice == "public" ]]; then
            print_warning "Making RPC port public without proper firewall rules can expose your node to DDoS attacks!"
            read -p "Are you sure you want to continue? [y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                RPC_PUBLIC=true
            else
                RPC_PUBLIC=false
            fi
        else
            RPC_PUBLIC=false
        fi
    fi
}

get_state_sync() {
    if [ "$NODE_TYPE" == "validator" ]; then
        # Automatically enable state sync for validator nodes
        STATE_SYNC_ENABLED=true
        echo "State sync bootstrapping automatically enabled for validator node"
    elif [ "$NODE_TYPE" != "historical" ]; then
        print_step "State sync configuration:"
        while true; do
            read -p "Do you want state sync bootstrapping to be turned on or off? [on/off]: " state_sync
            case $state_sync in
                on|ON)  STATE_SYNC_ENABLED=true; break;;
                off|OFF) STATE_SYNC_ENABLED=false; break;;
                *) echo "Please enter 'on' or 'off'";;
            esac
        done
    else
        STATE_SYNC_ENABLED=false
    fi
}

setup_avalanchego() {
    print_step "Setting up AvalancheGo from official Avalanche repository..."
    
    # Create directories
    mkdir -p "$HOME_DIR"/{db,configs,staking}

    if [ "$UPGRADE_MODE" = false ]; then
        # Fresh installation from official repository
        cd "$HOME"
        if [ -d "avalanchego" ]; then
            print_warning "AvalancheGo directory already exists. Removing..."
            rm -rf avalanchego
        fi
        git clone $AVALANCHE_REPO
        cd avalanchego
    fi
    
    # Get latest version from Avalanche
    get_latest_avalanchego_version
    
    # Checkout and build official version
    git checkout "v$AVALANCHEGO_VERSION"
    ./scripts/build.sh

    # Generate config
    generate_config

    # Setup systemd service
    setup_systemd_service

    # Generate staking keys for validator
    if [ "$NODE_TYPE" == "validator" ] && [ "$UPGRADE_MODE" = false ]; then
        generate_staking_keys
    fi
}

generate_config() {
    print_step "Generating node configuration..."
    
    CONFIG_FILE="$HOME_DIR/configs/node.json"
    
    # Base configuration
    cat > "$CONFIG_FILE" << EOL
{
    "network-id": "${NETWORK_ID}",
    "http-host": "",
    "http-port": 9650,
    "staking-port": 9651,
    "db-dir": "${HOME_DIR}/db",
    "log-level": "info",
    "public-ip": "${PUBLIC_IP}",
EOL

    # Node-specific configuration
    case $NODE_TYPE in
        "validator")
            cat >> "$CONFIG_FILE" << EOL
    "staking-enabled": true,
    "state-sync-enabled": ${STATE_SYNC_ENABLED},
    "api-admin-enabled": false,
    "api-ipcs-enabled": false,
    "api-keystore-enabled": false,
    "api-metrics-enabled": true
EOL
            ;;
        "historical")
            cat >> "$CONFIG_FILE" << EOL
    "index-enabled": true,
    "api-admin-enabled": true,
    "api-ipcs-enabled": true,
    "pruning-enabled": false,
    "c-chain-config": {
        "coreth-config": {
            "pruning-enabled": false,
            "allow-missing-tries": false,
            "populate-missing-tries": true,
            "snapshot-async": true,
            "snapshot-verification-enabled": false
        }
    }
EOL
            ;;
        "api")
            cat >> "$CONFIG_FILE" << EOL
    "state-sync-enabled": ${STATE_SYNC_ENABLED},
    "index-enabled": true,
    "api-admin-enabled": true,
    "api-info-enabled": true,
    "api-keystore-enabled": true,
    "api-metrics-enabled": true,
    "api-health-enabled": true,
    "api-ipcs-enabled": true
EOL
            ;;
    esac

    # Close JSON object
    echo "}" >> "$CONFIG_FILE"
}

setup_systemd_service() {
    print_step "Setting up systemd service..."
    
    sudo tee /etc/systemd/system/avalanchego.service > /dev/null << EOL
[Unit]
Description=AvalancheGo ${NODE_TYPE^} Node
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=$HOME/avalanchego/build/avalanchego --config-file=${HOME_DIR}/configs/node.json
Restart=always
RestartSec=1
TimeoutStopSec=300
LimitNOFILE=32768

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable avalanchego
}

generate_staking_keys() {
    print_step "Generating staking keys..."
    
    # Ensure the staking directory exists with correct permissions
    mkdir -p "${HOME_DIR}/staking"
    chmod 700 "${HOME_DIR}/staking"
    
    # Generate the staking keys
    if [ ! -f "${HOME_DIR}/staking/staker.key" ] || [ ! -f "${HOME_DIR}/staking/staker.crt" ]; then
        cd "$HOME/avalanchego"
        ./build/avalanchego \
            --staking-tls-cert-file="${HOME_DIR}/staking/staker.crt" \
            --staking-tls-key-file="${HOME_DIR}/staking/staker.key" \
            --chain-config-dir="" \
            --http-host="" \
            --http-port=9650 \
            --staking-port=9651 \
            --log-level=OFF \
            --genesis-file="" &

        # Wait a moment for the keys to be generated
        sleep 5
        
        # Kill the temporary node
        pkill -f avalanchego
        
        # Verify the keys were generated
        if [ ! -f "${HOME_DIR}/staking/staker.key" ] || [ ! -f "${HOME_DIR}/staking/staker.crt" ]; then
            print_error "Failed to generate staking keys"
            exit 1
        fi
        
        # Set correct permissions
        chmod 600 "${HOME_DIR}/staking/staker.key"
        chmod 644 "${HOME_DIR}/staking/staker.crt"
        
        echo "✓ Staking keys generated successfully"
    else
        echo "✓ Staking keys already exist"
    fi
}

configure_firewall() {
    print_step "Configuring firewall..."
    
    sudo apt-get install -y ufw
    sudo ufw allow 22/tcp
    sudo ufw allow 9651/tcp
    
    if [ "$RPC_PUBLIC" = true ]; then
        sudo ufw allow 9650/tcp
    fi
    
    sudo ufw --force enable
}

start_node() {
    print_step "Starting AvalancheGo node..."
    sudo systemctl start avalanchego
}

print_completion() {
    print_step "Installation completed!"
    echo "=================================================="
    echo "Node type: ${NODE_TYPE^}"
    echo "Network: $NETWORK_ID"
    if [ "$IS_STATIC_IP" = true ]; then
        echo "Public IP: $PUBLIC_IP"
    fi
    echo "=================================================="
    echo "Useful commands:"
    echo "- Check node status: sudo systemctl status avalanchego"
    echo "- View logs: sudo journalctl -u avalanchego -f"
    echo "- Stop node: sudo systemctl stop avalanchego"
    echo "- Start node: sudo systemctl start avalanchego"
    if [ "$NODE_TYPE" == "validator" ]; then
        echo -e "\nIMPORTANT: Backup your staking keys from ${HOME_DIR}/staking/"
    fi
    echo "=================================================="
}

restore_previous_version() {
    print_step "Restoring previous version..."
    
    # List available backups
    local BACKUP_DIR="$HOME_DIR"
    local backups=($(ls -d ${BACKUP_DIR}/backup_* 2>/dev/null))
    
    if [ ${#backups[@]} -eq 0 ]; then
        print_error "No backup versions found"
        exit 1
    fi
    
    echo "Available backups:"
    for i in "${!backups[@]}"; do
        local backup_date=$(basename "${backups[$i]}" | cut -d'_' -f2-)
        echo "$((i+1))) ${backup_date}"
    done
    
    # Get user selection
    local selection
    while true; do
        read -p "Select backup to restore [1-${#backups[@]}] or 'q' to quit: " selection
        if [[ "$selection" == "q" ]]; then
            exit 0
        elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#backups[@]}" ]; then
            break
        fi
        echo "Invalid selection. Please try again."
    done
    
    local SELECTED_BACKUP="${backups[$((selection-1))]}"
    
    # Stop the service
    print_step "Stopping AvalancheGo service..."
    sudo systemctl stop avalanchego
    
    # Backup current version before restoring
    local CURRENT_BACKUP="$HOME_DIR/backup_$(date +%Y%m%d_%H%M%S)_pre_restore"
    print_step "Creating backup of current version at: $CURRENT_BACKUP"
    mkdir -p "$CURRENT_BACKUP"
    cp -r "$HOME_DIR/configs" "$CURRENT_BACKUP/"
    if [ -d "$HOME_DIR/staking" ]; then
        cp -r "$HOME_DIR/staking" "$CURRENT_BACKUP/"
    fi
    
    # Restore selected backup
    print_step "Restoring from backup: $SELECTED_BACKUP"
    cp -r "$SELECTED_BACKUP/configs/"* "$HOME_DIR/configs/"
    if [ -d "$SELECTED_BACKUP/staking" ]; then
        cp -r "$SELECTED_BACKUP/staking/"* "$HOME_DIR/staking/"
    fi
    
    # Set correct permissions
    chmod 600 "$HOME_DIR/staking/staker.key"
    chmod 644 "$HOME_DIR/staking/staker.crt"
    
    # Start the service
    print_step "Starting AvalancheGo service..."
    sudo systemctl start avalanchego
    
    print_step "Restore completed successfully!"
    echo "Previous version backed up to: $CURRENT_BACKUP"
    echo "Restored from: $SELECTED_BACKUP"
}

main() {
    print_banner
    
    # Check if restore option is requested
    if [ "$1" == "--restore" ]; then
        restore_previous_version
        exit 0
    fi
    
    # Check for existing installation and updates
    if check_for_updates; then
        upgrade_avalanchego
        exit 0
    fi
    
    check_requirements
    install_dependencies
    get_node_type
    get_network
    get_ip_config
    get_rpc_config
    get_state_sync
    setup_avalanchego
    configure_firewall
    start_node
    print_completion
}

# Pass command line arguments to main
main "$@" 