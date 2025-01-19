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

## Usage

1. Run the script with sudo privileges
2. Select your desired node type from the menu
3. Choose network (Mainnet or Fuji)
4. Follow the prompts to complete installation

### Menu Options
1. Install/Upgrade Validator Node
2. Install/Upgrade Historical Node
3. Install/Upgrade API Node
4. Manual Configuration
5. Backup Node
6. Restore Node
7. Monitor Node Status
8. Exit

## Maintenance

### Backup
- Automatically stops the service
- Creates timestamped backup (YYYYMMDD_HHMMSS format)
- Restarts the service
- Stores backups in `/home/avax/avalanche-backup`

### Restore
- Lists available backups
- Allows selection of backup file
- Handles service management during restore
- Verifies backup integrity
- Maintains proper permissions

### Monitoring
- Service status checking
- Bootstrap progress tracking
- Chain status verification
- Real-time node information

## Security Features

- Dedicated system user (avax)
- Secure default configurations
- Private RPC for validator nodes
- Limited API exposure where appropriate
- File permission management
- Network security settings

## Support

For support, please contact Rise & Shine Management.

## License

This software is proprietary and confidential. Unauthorized copying, modification, distribution, or use of this software, via any medium, is strictly prohibited. All rights reserved by Rise & Shine Management.

## Author

Developed by Nodestrdamus for Rise & Shine Management. 