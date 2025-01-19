# Avalanche Node Deployment Script

A comprehensive installation and management script for deploying various types of Avalanche nodes. This script simplifies the process of setting up and managing Validator, Historical, and API nodes on the Avalanche network.

## Features

- **Multiple Node Types**:
  - Validator Node (with automatic state sync and private RPC)
  - Historical Node (with full indexing)
  - API Node (with public endpoints)
  - Manual Configuration Option

- **System Requirements Check**:
  - CPU: Minimum 8 cores recommended
  - RAM: Minimum 16 GB recommended
  - Storage: Minimum 1 TB recommended
  - Automatic system verification
  - Warning notifications for insufficient resources

- **Network Environment Support**:
  - Residential Network (Dynamic IP)
  - Cloud/Datacenter (Static IP)
  - Automatic IP detection and configuration
  - OpenDNS resolution for dynamic IPs

- **Automated Setup**:
  - Go 1.22.8 installation and configuration
  - Dependency management (gcc, g++, make)
  - User creation and permission handling
  - Directory structure setup
  - Systemd service configuration
  - Network selection (Mainnet/Fuji)

- **Management Features**:
  - One-click installation and upgrades
  - Automated backup with timestamps
  - Restore functionality
  - Service management
  - Node monitoring and status checks
  - Bootstrap progress tracking

## Prerequisites

- Ubuntu Server 20.04.6 or 24.04.1
- Root or sudo access
- Internet connectivity
- Minimum system requirements:
  - 8 CPU cores
  - 16 GB RAM
  - 1 TB storage
  - Reliable network connection

## Quick Start

```bash
wget -nd -m https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/install-avalanche-node.sh
chmod 755 install-avalanche-node.sh
sudo ./install-avalanche-node.sh
```

## Installation Process

1. **System Check**:
   - Verifies CPU, RAM, and storage requirements
   - Checks and installs dependencies
   - Sets up system user and directories

2. **Network Selection**:
   - Choose between Mainnet and Fuji Testnet
   - Detailed descriptions of each network provided

3. **Environment Setup**:
   - Select between residential or datacenter deployment
   - Automatic IP detection for static IPs
   - Configuration of network settings

4. **Node Configuration**:
   - Automated setup based on node type
   - Security-focused default settings
   - Custom chain configurations

## Node Types and Configurations

### Validator Node
- State sync enabled
- Private RPC (localhost only)
- Minimal API exposure
- Optimized for validation
- Metrics enabled
- Secure default settings

### Historical Node
- Full indexing enabled
- Pruning disabled
- Complete transaction history
- API admin enabled
- Custom chain configuration support
- Metrics monitoring

### API Node
- Public RPC endpoints
- All APIs enabled
- State sync enabled
- Full indexing
- IPCS enabled
- Metrics and monitoring

## Post-Installation Information

After installation, the script provides comprehensive information about your node:

### 1. Node Identification
- Display of Node ID
- Network type (Mainnet/Fuji)
- Node type (Validator/Historical/API)

### 2. Bootstrap Status
- Real-time bootstrap progress
- Status for all chains (P-Chain, X-Chain, C-Chain)
- Estimated completion indicators

### 3. Management Commands
```bash
# Start the node
sudo systemctl start avalanchego

# Stop the node
sudo systemctl stop avalanchego

# Restart the node
sudo systemctl restart avalanchego

# Check node status
sudo systemctl status avalanchego

# Monitor logs
sudo journalctl -u avalanchego -f

# Check bootstrap progress
curl -X POST --data '{
    "jsonrpc":"2.0",
    "id"     :1,
    "method" :"info.isBootstrapped",
    "params": {
        "chain":"X"
    }
}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info
```

### 4. Node-Specific Information
- Validator: Staking instructions and NodeID usage
- API: Available endpoints and access information
- Historical: Data management and indexing details

## Directory Structure

```
/home/avax/
├── .avalanchego/
│   ├── configs/
│   │   ├── node.json
│   │   └── chains/
│   └── db/
├── avalanchego/
└── avalanche-backup/
```

## Maintenance

### Backup
- Automated backup creation
- Timestamped backup files (YYYYMMDD_HHMMSS format)
- Safe service management during backup
- Backup storage in `/home/avax/avalanche-backup`

### Restore
- List of available backups
- Guided restoration process
- Automatic service management
- Permission preservation

### Monitoring
- Service status checking
- Bootstrap progress tracking
- Chain status verification
- Real-time node information
- Resource usage monitoring

## Security Features

- Dedicated system user (avax)
- Secure default configurations
- Private RPC for validator nodes
- Limited API exposure where appropriate
- File permission management
- Network security settings
- Automated security configurations

## Support

For support, please contact Rise & Shine Management.

## Documentation

For detailed information about Avalanche nodes, visit:
- [Avalanche Documentation](https://docs.avax.network/)
- [Node Operation Guide](https://docs.avax.network/nodes)
- [Validator Guide](https://docs.avax.network/nodes/validate)

## License

This software is proprietary and confidential. Unauthorized copying, modification, distribution, or use of this software, via any medium, is strictly prohibited. All rights reserved by Rise & Shine Management.

## Author

Developed by Nodestrdamus for Rise & Shine Management. 