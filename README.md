# Avalanche Node Deployment Script

This repository contains a single-line installation script for deploying various types of Avalanche nodes. The script supports deploying Validator Nodes, Historical Nodes, API Nodes, and allows for manual configuration.

## Quick Install

You can install an Avalanche node using this one-liner:

```bash
curl -sSfL https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/install-avalanche.sh | bash
```

## Features

- **Multiple Node Types**:
  - Validator Node (State Sync ON, Private RPC)
  - Historical Node
  - API Node
  - Manual Configuration

- **Automatic Updates**: Pulls the latest version of AvalancheGo
- **Backup System**: Automatically backs up existing nodes before upgrades
- **Systemd Integration**: Runs as a background service
- **Security Focused**: Validator nodes configured with private RPC by default

## Node Types and Configurations

### Validator Node
- State Sync: Enabled
- RPC: Private (localhost only)
- Admin API: Disabled
- Indexing: Disabled

### Historical Node
- State Sync: Disabled
- Pruning: Disabled
- Admin API: Enabled
- Indexing: Enabled

### API Node
- State Sync: Enabled
- RPC: Public
- Admin API: Enabled
- Indexing: Enabled

### Manual Configuration
- Provides basic configuration
- Allows for custom modifications

## System Requirements

- Linux-based operating system
- `curl` or `wget`
- `systemd`
- Sufficient disk space (recommended: 200GB+)
- Minimum 8GB RAM

## Post-Installation

The script will:
1. Install AvalancheGo in `$HOME/avalanchego`
2. Create configuration in `$HOME/.avalanchego/configs`
3. Set up a systemd service
4. Start the node automatically

## Maintenance

### Check Node Status
```bash
sudo systemctl status avalanchego
```

### View Logs
```bash
sudo journalctl -u avalanchego -f
```

### Restart Node
```bash
sudo systemctl restart avalanchego
```

### Stop Node
```bash
sudo systemctl stop avalanchego
```

## Backup Location

Backups are stored in `$HOME/avalanche-backup` with timestamps.

## Security Considerations

- For validator nodes, RPC endpoints are private by default
- Admin API is disabled for validator nodes
- Backup your node keys and configurations regularly
- Use appropriate firewall rules

## Support

For issues and feature requests, please open an issue in the GitHub repository.

## License

MIT License 