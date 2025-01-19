# Avalanche Node Deployment Script

© 2024 Rise & Shine Management. All Rights Reserved.

A professional-grade installation script for deploying and managing Avalanche nodes on Ubuntu systems. This script streamlines the process of setting up validator, historical, or API nodes on both mainnet and testnet environments.

## Features

### Node Types
- **Validator Node**: Secure configuration optimized for network validation
- **Historical Node**: Full indexing enabled for historical data access
- **API Node**: Public endpoint configuration with admin API access

### Network Options
- Mainnet deployment
- Fuji Testnet deployment

### IP Configuration
- Residential networks (Dynamic IP with OpenDNS)
- Cloud/Datacenter (Static IP auto-detection)

### Management Features
- Automated dependency installation
- Systemd service configuration
- One-click upgrades
- Clean removal/reinstallation
- Automatic service recovery
- Comprehensive logging

## Quick Installation

Deploy your Avalanche node with a single command:

```bash
wget -nd -m https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/install-avalanche-node.sh;\
chmod 755 install-avalanche-node.sh;\
./install-avalanche-node.sh
```

## System Requirements

### Minimum Hardware
- CPU: 8 cores / 16 threads
- RAM: 16 GB
- Storage: 1 TB SSD (NVMe recommended)
- Network: 1 Gbps connection

### Software
- Ubuntu 20.04 LTS or 24.04 LTS
- Root privileges required

## Node Management

### Basic Commands
```bash
# Start your node
sudo systemctl start avalanchego

# Stop your node
sudo systemctl stop avalanchego

# Check node status
sudo systemctl status avalanchego

# View real-time logs
sudo journalctl -u avalanchego -f
```

### Maintenance
- **Upgrade**: Re-run the installation script and select the upgrade option
- **Reinstall**: Choose the clean installation option during script execution
- **Remove**: Script provides clean removal of all components

## Directory Structure

```
/opt/avalanchego/
├── avalanchego/
│   ├── build/
│   └── scripts/
└── [node data]
```

## Security Considerations

- API node exposes public endpoints - ensure proper firewall configuration
- Validator nodes maintain restricted access by default
- System user 'avalanche' created with minimal privileges
- Automatic service restart on failure

## Troubleshooting

1. **Node Won't Start**
   - Check logs: `sudo journalctl -u avalanchego -n 100`
   - Verify permissions: `ls -la /opt/avalanchego`
   - Ensure ports are available: `netstat -tulpn | grep 9650`

2. **Bootstrap Issues**
   - Monitor progress in logs
   - Verify network connectivity
   - Check disk space: `df -h`

## License

Proprietary software of Rise & Shine Management. All rights reserved.

This software and associated documentation files (the "Software") are the exclusive property of Rise & Shine Management. The Software is protected by copyright laws and international copyright treaties, as well as other intellectual property laws and treaties.

Unauthorized copying, modification, distribution, or use of this Software, via any medium, is strictly prohibited without the express written permission of Rise & Shine Management.

## Support

For technical support or licensing inquiries:
- Rise & Shine Management
- Website: [Your Website]
- Email: [Support Email]

## Acknowledgments

Built on the AvalancheGo platform:
- [AvalancheGo Repository](https://github.com/ava-labs/avalanchego)
- [Avalanche Documentation](https://docs.avax.network/) 