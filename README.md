# Avalanche Node Deployment Script

A comprehensive installation script for deploying Avalanche nodes with support for multiple node types and configurations.

## Features

- **Multiple Node Types**:
  - **Validator Node**: For network validation with staking capabilities
  - **Historical Node**: Full archive node with complete historical data
  - **API Node**: General purpose RPC node with API access

- **Network Support**:
  - Mainnet
  - Fuji (Testnet)

- **Automatic Configuration**:
  - Dynamic/Static IP configuration for validators
  - Public/Private RPC access control
  - Secure firewall setup
  - Systemd service configuration

- **Security Features**:
  - Automatic staking key backup and restoration
  - Secure permission management
  - Restrictive firewall rules
  - Private RPC by default

## System Requirements

- **Operating System**: Ubuntu 20.04 or 24.04 LTS
- **Hardware**:
  - CPU: 8 cores / 16 threads
  - RAM: 16 GB
  - Storage: 1 TB SSD (recommended)
  - Network: Stable connection with minimum 1 Gbps bandwidth

## Quick Start

1. Download the script:
   ```bash
   wget https://raw.githubusercontent.com/YOUR_USERNAME/avalanche-node-deployment/main/avalanche-node-installer.sh
   ```

2. Make it executable:
   ```bash
   chmod +x avalanche-node-installer.sh
   ```

3. Run the installer:
   ```bash
   ./avalanche-node-installer.sh
   ```

## Installation Process

The script will guide you through the following steps:

1. **Node Type Selection**:
   - Validator Node
   - Historical RPC Node
   - API Node

2. **Network Selection**:
   - Mainnet
   - Fuji (Testnet)

3. **IP Configuration** (for Validator nodes):
   - Residential IP (Dynamic)
   - Static IP

4. **RPC Access Configuration**:
   - Private (recommended for validators)
   - Public (for API/Historical nodes)

## Node Types

### Validator Node
- Participates in network consensus
- Requires staking
- Private RPC by default
- Automatic staking key management
- Dynamic IP support for residential connections

### Historical Node
- Maintains complete historical data
- Public RPC enabled
- Pruning disabled
- State sync disabled
- Full indexing enabled

### API Node
- General purpose RPC functionality
- Public RPC enabled
- Pruning enabled
- State sync enabled
- Optimized for API requests

## Configuration

The script automatically generates appropriate configurations based on node type:

```json
{
    "network-id": "<network>",
    "http-host": "<based on RPC access>",
    "http-port": 9650,
    "staking-port": 9651,
    "db-dir": "<path>/db",
    "log-level": "info",
    // Additional type-specific settings
}
```

## Security

1. **Firewall Configuration**:
   - SSH (22/tcp)
   - P2P Communication (9651/tcp)
   - API Access (9650/tcp) - only if RPC is public

2. **Staking Keys** (Validator nodes):
   - Automatic backup during upgrades
   - Secure permissions (600)
   - Protected storage location

3. **RPC Access**:
   - Private by default for validators
   - Warning when enabling public access
   - Configurable per node type

## Monitoring

The script provides several monitoring options:

1. **Log Monitoring**:
   ```bash
   sudo journalctl -u avalanchego -f
   ```

2. **Service Status**:
   ```bash
   sudo systemctl status avalanchego
   ```

3. **Bootstrap Progress**:
   ```bash
   curl -X POST --data '{
       "jsonrpc":"2.0",
       "id":1,
       "method":"info.isBootstrapped",
       "params":{"chain":"P"}
   }' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info
   ```

4. **System Resources**:
   ```bash
   htop
   ```

## Service Management

```bash
# Start the node
sudo systemctl start avalanchego

# Stop the node
sudo systemctl stop avalanchego

# Restart the node
sudo systemctl restart avalanchego

# Check status
sudo systemctl status avalanchego
```

## Backup and Recovery

The script automatically handles:
- Staking key backup during upgrades
- Configuration preservation
- Installation backups with timestamps

Backups are stored in:
```
$HOME/avalanchego_backup_<timestamp>/
```

## Troubleshooting

1. **Node Won't Start**:
   - Check logs: `sudo journalctl -u avalanchego -f`
   - Verify permissions: `ls -la $HOME/.avalanchego/`
   - Check service status: `sudo systemctl status avalanchego`

2. **RPC Issues**:
   - Verify RPC configuration in node.json
   - Check firewall rules: `sudo ufw status`
   - Ensure correct http-host setting

3. **Bootstrap Issues**:
   - Monitor logs for progress
   - Check network connectivity
   - Verify chain status for P, X, and C chains

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support and questions:
1. Open an issue in the repository
2. Check existing documentation
3. Review troubleshooting guide

## References

- [Official Avalanche Documentation](https://docs.avax.network/)
- [Node Operation Guides](https://docs.avax.network/nodes) 