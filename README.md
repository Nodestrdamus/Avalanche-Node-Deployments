# Avalanche Node Deployment

A unified installer script for deploying and managing Avalanche nodes with different configurations. This tool supports deploying validator nodes, historical nodes, and API nodes with a single command, and includes automatic version management and upgrades directly from Avalanche's official repository.

## Installation Methods

### Method 1: Direct Download and Execute
```bash
wget https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/avalanche-node-installer.sh
chmod 755 avalanche-node-installer.sh
./avalanche-node-installer.sh
```

### Method 2: Curl and Execute (One-liner)
```bash
curl -L https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/avalanche-node-installer.sh | bash
```

### Method 3: Clone Repository
```bash
git clone https://github.com/Nodestrdamus/Avalanche-Node-Deployments.git
cd Avalanche-Node-Deployments
chmod 755 avalanche-node-installer.sh
./avalanche-node-installer.sh
```

## Features

- **Official Avalanche Integration**:
  - Pulls directly from Avalanche's official repository
  - Uses official releases and versions
  - Follows Avalanche's recommended configurations
  - Compatible with official Avalanche updates
- **Single Command Installation**: Deploy any type of Avalanche node with a single command
- **Automatic Version Management**:
  - Fetches latest AvalancheGo version from official Avalanche releases
  - Checks for updates on each run
  - Performs in-place upgrades with configuration preservation
  - Creates automatic backups before upgrades
- **Multiple Node Types**:
  - Validator Node (for staking)
  - Historical Node (full archive)
  - API Node (RPC endpoint)
- **Network Selection**:
  - Mainnet
  - Fuji (Testnet)
  - Local
- **Automatic Configuration**:
  - System requirements verification
  - Dependencies installation
  - Network configuration
  - Firewall setup
  - Systemd service creation

## Version Management

The script automatically manages AvalancheGo versions by:
1. Checking Avalanche's official GitHub releases
2. Downloading official binaries and source code
3. Following Avalanche's recommended upgrade paths
4. Maintaining compatibility with the Avalanche network

### Version Compatibility

- The script always uses official Avalanche releases
- Version checks ensure compatibility with the network
- Upgrades follow Avalanche's recommended procedures
- All configurations match official Avalanche specifications

## System Requirements

- Ubuntu 24.04.1 Server
- Minimum 8 CPU cores (recommended)
- Minimum 16GB RAM (recommended)
- Minimum 1TB free disk space (recommended)

## Usage

### Fresh Installation

1. Run the installer:
   ```bash
   curl -L https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/avalanche-node-installer.sh | bash
   ```

2. Follow the interactive prompts to select:
   - Node type
   - Network (Mainnet/Fuji/Local)
   - Network configuration (Static/Dynamic IP)
   - RPC access configuration
   - State sync options (if applicable)

3. The installer will automatically:
   - Check system requirements
   - Install dependencies
   - Set up AvalancheGo
   - Configure the node
   - Set up systemd service
   - Configure firewall
   - Start the node

### Checking for Updates

Run the installer script at any time to check for updates:
```bash
bash avalanche-node-installer.sh
```

The script will:
1. Check your current AvalancheGo version
2. Compare with the latest available version
3. Prompt for upgrade if a newer version is available

### Upgrade Process

When an upgrade is available, the script will:
1. Create a backup of your current configuration
2. Stop the running node
3. Update to the latest version
4. Preserve all configurations and staking keys
5. Restart the node automatically

Backup locations:
- Configurations: `~/.avalanchego/backup_TIMESTAMP/configs/`
- Staking keys: `~/.avalanchego/backup_TIMESTAMP/staking/` (for validator nodes)

### Restore Previous Version

If you need to restore a previous version:

```bash
./avalanche-node-installer.sh --restore
```

This will:
1. List all available backups with timestamps
2. Let you select which backup to restore
3. Create a backup of the current version before restoring
4. Restore the selected backup
5. Restart the node automatically

Backups are stored in:
- `~/.avalanchego/backup_TIMESTAMP/` - Regular backups from updates
- `~/.avalanchego/backup_TIMESTAMP_pre_restore/` - Backups created before restores

Each backup contains:
- Node configurations
- Staking keys (for validator nodes)
- Network settings

## Node Management

After installation, use these commands to manage your node:

```bash
# Check node status
sudo systemctl status avalanchego

# View logs
sudo journalctl -u avalanchego -f

# Stop node
sudo systemctl stop avalanchego

# Start node
sudo systemctl start avalanchego

# Restart node
sudo systemctl restart avalanchego
```

## Security Considerations

- The installer runs with user privileges and requires sudo access for specific operations
- Firewall is automatically configured based on node type
- RPC access can be restricted to private network only
- For validator nodes, backup your staking keys from ~/.avalanchego/staking/
- Automatic backups are created before each upgrade

## Troubleshooting

Common issues and solutions:

1. **Installation fails**: Check system requirements and ensure you're running Ubuntu 24.04.1
2. **Node won't start**: Check logs with `sudo journalctl -u avalanchego -f`
3. **Connection issues**: Verify firewall configuration and network settings
4. **Upgrade fails**: 
   - Check the backup directory for your previous configuration
   - Ensure sufficient disk space for the upgrade
   - Verify network connectivity to GitHub

## License

Proprietary software - Copyright © 2024 Rise & Shine Management. All rights reserved.

This software and associated documentation files are proprietary and confidential. Unauthorized copying, distribution, modification, public display, or public performance of this software is strictly prohibited. 