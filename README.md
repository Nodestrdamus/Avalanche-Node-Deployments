# Avalanche Node Deployment Scripts

A comprehensive toolset for deploying and managing Avalanche nodes with support for multiple node types and automated updates.

## Features

- **Multiple Node Types**:
  - Validator Node (for network validation)
  - Historical RPC Node (for full historical data)
  - API Node (for general RPC functionality)
- **Network Support**:
  - Mainnet
  - Fuji (Testnet)
- **Automated Installation**:
  - One-command installation process
  - Automatic dependency management
  - Systemd service configuration
- **Security Features**:
  - Automatic firewall configuration
  - Secure staking key generation
  - Proper permission management
- **Update Management**:
  - In-place upgrades
  - Automatic backup before updates
  - Rollback capability
  - Version management

## System Requirements

- **Operating System**: Ubuntu 20.04 or 24.04 LTS
- **Minimum Hardware**:
  - CPU: 8 cores / 16 threads
  - RAM: 16 GB
  - Storage: 1 TB SSD (recommended)
  - Network: Stable connection with minimum 1 Gbps bandwidth

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/avalanche-node-deployment.git
   cd avalanche-node-deployment
   ```

2. Make the script executable:
   ```bash
   chmod +x avalanche-node-installer.sh
   ```

3. Run the installer:
   ```bash
   ./avalanche-node-installer.sh
   ```

## Node Types

### 1. Validator Node
- Participates in network consensus
- Requires staking
- More restrictive security settings
- Pruning enabled for optimal performance
- Configuration optimized for validation

### 2. Historical RPC Node
- Maintains full historical data
- No staking required
- API and IPCS enabled
- Pruning disabled
- State sync disabled
- Ideal for historical data queries

### 3. API Node
- General RPC functionality
- No staking required
- API enabled
- Pruning enabled
- State sync enabled
- Optimized for API requests

## Installation Process

1. **System Check**:
   - Verifies Ubuntu version
   - Checks if not running as root
   - Validates system requirements

2. **Dependency Installation**:
   - Go ${GOVERSION}
   - Build tools
   - Required packages
   - Firewall setup

3. **Node Configuration**:
   - Network selection (Mainnet/Fuji)
   - Node type selection
   - Directory structure creation
   - Configuration file generation

4. **Service Setup**:
   - Systemd service configuration
   - Automatic startup
   - Service management commands

## Update Management

The script includes a robust update management system:

1. **Check for Updates**:
   ```bash
   ./avalanche-node-installer.sh --update
   ```

2. **Update Process**:
   - Automatic version detection
   - Backup creation
   - In-place upgrade
   - Configuration preservation
   - Service restart

3. **Rollback Capability**:
   - Automatic rollback on failure
   - Configuration restoration
   - Version control

## Configuration

Node configurations are automatically generated based on node type. Key configurations:

```json
{
    "network-id": "<network>",
    "http-host": "",
    "http-port": 9650,
    "staking-port": 9651,
    "db-dir": "<path>/db",
    "log-level": "info",
    "api-admin-enabled": false,
    "api-metrics-enabled": true
    // Additional type-specific settings
}
```

## Firewall Configuration

The script automatically configures UFW:
- SSH (22/tcp)
- P2P Communication (9651/tcp)
- API Access (9650/tcp) - for Historical and API nodes

## Monitoring and Management

### Service Management
```bash
# Check status
sudo systemctl status avalanchego

# View logs
sudo journalctl -u avalanchego -f

# Start/Stop/Restart
sudo systemctl start avalanchego
sudo systemctl stop avalanchego
sudo systemctl restart avalanchego
```

### Bootstrap Status
```bash
# Check chain bootstrap status
curl -X POST --data '{
    "jsonrpc":"2.0",
    "id":1,
    "method":"info.isBootstrapped",
    "params":{"chain":"X"}
}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info
```

### RPC Endpoints
- P-Chain: `localhost:9650/ext/bc/P`
- X-Chain: `localhost:9650/ext/bc/X`
- C-Chain: `localhost:9650/ext/bc/C/rpc`

## Backup and Recovery

The script automatically creates backups during updates:
- Configuration files
- Staking keys (for validator nodes)
- Chain configurations
- Backup location: `$HOME/.avalanchego/backup_<timestamp>`

## Troubleshooting

1. **Node Won't Start**:
   - Check logs: `sudo journalctl -u avalanchego -f`
   - Verify configuration in `$HOME/.avalanchego/configs/node.json`
   - Ensure proper permissions on staking keys

2. **Update Fails**:
   - Script automatically rolls back to previous version
   - Check logs for specific errors
   - Verify network connectivity
   - Ensure sufficient disk space

3. **Bootstrap Issues**:
   - Full bootstrapping can take several days
   - Monitor progress through logs
   - Check network connectivity
   - Verify hardware meets requirements

## Security Considerations

1. **Staking Keys** (Validator Nodes):
   - Stored in `$HOME/.avalanchego/staking/`
   - Permissions set to 600
   - Backup keys securely
   - Never share private keys

2. **Firewall Rules**:
   - Validator nodes: Restricted API access
   - Historical/API nodes: Open API port
   - All nodes: P2P port open

3. **Best Practices**:
   - Regular backups
   - Monitor system resources
   - Keep system updated
   - Use strong SSH keys

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For support and questions:
1. Open an issue in the repository
2. Check existing documentation
3. Review troubleshooting guide 