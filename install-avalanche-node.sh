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
AVALANCHEGO_HOME="$HOME_DIR/AvalancheGo"
AVALANCHE_DATA_DIR="$AVALANCHEGO_HOME/.avalanchego"
CONFIG_DIR="$AVALANCHE_DATA_DIR/configs"
CONFIG_FILE="$CONFIG_DIR/node.json"
CHAIN_DATA_DIR="$AVALANCHE_DATA_DIR/db"
BACKUP_DIR="$AVALANCHEGO_HOME/backups"
LOG_DIR="$AVALANCHEGO_HOME/logs"
BIN_DIR="$AVALANCHEGO_HOME/bin"
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
    
    # Set permissions
    chown -R "$USER:$USER" "$HOME_DIR"
    chmod 750 "$AVALANCHEGO_HOME"
    chmod 750 "$AVALANCHE_DATA_DIR"
    chmod 750 "$CONFIG_DIR"
    chmod 750 "$BACKUP_DIR"
    chmod 750 "$LOG_DIR"
    chmod 750 "$BIN_DIR"
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
        print_message "Created user: $USER" "$GREEN"
    fi
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
    print_message "Installing/Upgrading AvalancheGo..." "$YELLOW"
    su - "$USER" -c "
        cd $AVALANCHEGO_HOME
        if [ ! -d src ]; then
            mkdir -p src
            cd src
            git clone https://github.com/ava-labs/avalanchego.git
        fi
        cd src/avalanchego
        git fetch
        git checkout master
        git pull
        ./scripts/build.sh
        cp build/avalanchego $BIN_DIR/
        chmod 750 $BIN_DIR/avalanchego
    "
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
ExecStart=$BIN_DIR/avalanchego --config-file=$CONFIG_FILE
LimitNOFILE=32768
StandardOutput=append:$LOG_DIR/avalanchego.log
StandardError=append:$LOG_DIR/avalanchego.error.log

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
    
    print_message "\nNode Installation Complete!" "$GREEN"
    print_message "\nImportant Node Information:" "$YELLOW"
    echo -e "\n1. Node ID:"
    echo "   $(journalctl -u avalanchego | grep "NodeID-" | tail -n 1 | awk -F'NodeID-' '{print "NodeID-"$2}')"
    
    echo -e "\n2. Node Status:"
    echo "   Current status: $(systemctl is-active avalanchego)"
    
    echo -e "\n3. Bootstrap Status:"
    echo "   Checking bootstrap progress for P-Chain, X-Chain, and C-Chain..."
    for chain in "P" "X" "C"; do
        bootstrap_status=$(curl -s -X POST --data '{
            "jsonrpc":"2.0",
            "id"     :1,
            "method" :"info.isBootstrapped",
            "params": {
                "chain":"'"$chain"'"
            }
        }' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info | grep -o 'true\|false')
        echo "   $chain-Chain: ${bootstrap_status:-Checking...}"
    done
    
    print_message "\nUseful Commands:" "$YELLOW"
    echo -e "\n1. Service Management:"
    echo "   Start node:   sudo systemctl start avalanchego"
    echo "   Stop node:    sudo systemctl stop avalanchego"
    echo "   Restart node: sudo systemctl restart avalanchego"
    echo "   View status:  sudo systemctl status avalanchego"
    
    echo -e "\n2. Log Monitoring:"
    echo "   View logs:    sudo journalctl -u avalanchego -f"
    
    echo -e "\n3. Configuration:"
    echo "   Config file:  $CONFIG_FILE"
    echo "   Data dir:     $CHAIN_DATA_DIR"
    
    echo -e "\n4. Bootstrap Progress:"
    echo "   Check status: curl -X POST --data '{
        \"jsonrpc\":\"2.0\",
        \"id\"     :1,
        \"method\" :\"info.isBootstrapped\",
        \"params\": {
            \"chain\":\"X\"
        }
    }' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info"
    
    if [ "$node_type" = "validator" ]; then
        echo -e "\n5. Validator Info:"
        echo "   - Your NodeID is required for staking"
        echo "   - Ensure node is fully bootstrapped before staking"
        echo "   - Keep your node running and maintain good network connectivity"
    fi
    
    print_message "\nNext Steps:" "$GREEN"
    case $node_type in
        "validator")
            echo "1. Wait for node to finish bootstrapping"
            echo "2. Visit https://wallet.avax.network/ to stake your AVAX"
            echo "3. Use your NodeID when adding a validator"
            ;;
        "api")
            echo "1. Wait for node to finish bootstrapping"
            echo "2. API endpoints will be available at: http://localhost:9650"
            echo "3. Monitor your node's performance and resource usage"
            ;;
        "historical")
            echo "1. Wait for node to finish bootstrapping and indexing"
            echo "2. Monitor disk usage as the node accumulates historical data"
            echo "3. Use API endpoints to query historical transactions"
            ;;
    esac
    
    print_message "\nNeed help? Check the documentation at https://docs.avax.network/" "$YELLOW"
    
    # Prompt to save information
    echo -e "\nWould you like to save this information to a file? [y/n]"
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
    check_root
    check_system_requirements
    
    # 2. Setup system
    setup_user
    create_directories
    install_dependencies
    
    # 3. Install AvalancheGo
    install_avalanchego
    
    # 4. Configure node
    network_id=$(select_network)
    network_env=$(select_network_environment)
    configure_node "$node_type" "$network_id" "$network_env"
    
    # 5. Setup service and start node
    setup_service "$network_id"
    
    # 6. Display node information
    print_message "Installation/Upgrade completed successfully!" "$GREEN"
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