# Avalanche Node Management Script

A comprehensive management script for Avalanche nodes on Ubuntu Server, providing full lifecycle management including deployment, backup, and restore functionality.

## Table of Contents
1. [Features](#features)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Node Types](#node-types)
5. [Security Guide](#security-guide)
6. [Backup & Recovery](#backup--recovery)
7. [Operations Guide](#operations-guide)
8. [Technical Specifications](#technical-specifications)
9. [Troubleshooting](#troubleshooting)
10. [Support](#support)

## Features

### Core Features
- Automated installation and configuration
- Multiple node type support (Validator, API, Archive)
- Secure deployment with hardened defaults
- Automatic version management
- Performance optimization
- Local and remote backup solutions
- Automatic node detection and configuration

### Installation Features
- Official Avalanche installer integration
- Interactive configuration process
- Node type-specific optimizations
- Automatic security hardening
- Existing deployment detection
- Configuration preservation
- Version compatibility verification

### Backup Solutions
- **Local Backup**
  - Timestamped backups with integrity verification
  - Critical file preservation
  - Database backup options (full or incremental)
  - Automatic permission management
  - Backup rotation and cleanup

- **Remote Backup**
  - Secure SCP transfers with key authentication
  - Remote node management
  - Automated backup scheduling
  - Cross-node synchronization
  - Bandwidth-optimized transfers

### Security Features
- Automatic firewall configuration
- Fail2ban integration for public nodes
- Secure file permissions
- Regular security updates
- Access logging
- Network isolation options

## Prerequisites

### System Requirements
- Ubuntu Server 20.04 LTS (Focal) or 22.04 LTS (Jammy)
- Hardware:
  - CPU: 8 cores / 16 threads (AMD Ryzen 7/Intel Xeon)
  - RAM: 16 GB minimum (32 GB recommended)
  - Storage:
    - Validator/API: 1 TB NVMe SSD (10,000+ IOPS)
    - Archive: 2 TB NVMe SSD (15,000+ IOPS)
  - Network: 10+ Mbps dedicated connection
  - Latency: < 20ms to major network hubs

### Network Requirements
- Required Ports:
  - 9650/tcp: HTTP/HTTPS API
  - 9651/tcp: Staking/P2P
  - 22/tcp: SSH (management)

## Quick Start

### Fresh Installation
```bash
# Download
wget -O avalanche-deploy.sh https://raw.githubusercontent.com/Nodestrdamus/Avalanche-Node-Deployments/main/avalanche-deploy.sh

# Make executable
chmod +x avalanche-deploy.sh

# Run
sudo ./avalanche-deploy.sh
```

### Backup Operations
```bash
# During script execution, select:
# 1. Backup Operations
# 2. Choose backup type:
#    - Node identity files only
#    - Full database backup
```

## Security Guide

### Node Security
- Automatic firewall configuration
- Fail2ban integration for public nodes
- Secure file permissions
- Regular security updates
- Access logging
- Network isolation options

### Backup Security
- Secure file storage
- Access control enforcement
- Automated cleanup
- Backup verification
- Token rotation support

## Backup & Recovery

### Critical Files
Located in `/home/avalanche/.avalanchego/staking/`:
- `staker.crt`: Node certificate
- `staker.key`: Node private key
- `signer.key`: BLS key
- `.avalanchego/config.json`: Node configuration

### Backup Methods

#### Local Backup
```bash
# Create backup
Select "Local backup" from backup menu

# Restore
Select "Local restore" from restore menu
```

#### Remote Backup
```bash
# Backup to remote
Select "Remote backup" from backup menu

# Restore from remote
Select "Remote restore" from restore menu
```

### Recovery Procedures
1. Stop node service
2. Select appropriate restore method
3. Verify file permissions
4. Start node service
5. Verify node operation

## Operations Guide

### Service Management
```bash
# Service Control
sudo systemctl start avalanchego
sudo systemctl stop avalanchego
sudo systemctl restart avalanchego
sudo systemctl status avalanchego

# Log Management
sudo journalctl -u avalanchego
sudo journalctl -u avalanchego -f
sudo journalctl -u avalanchego -n 100
sudo journalctl -u avalanchego --since '1 hour ago'
```

## Technical Specifications

### Performance Metrics
- Transaction processing: 4,500+ tx/second
- Block time: 2 seconds
- Time to finality: 2-3 seconds
- API response time: < 500ms

### System Configuration
```bash
# File Limits
avalanche soft nofile 32768
avalanche hard nofile 65536

# Network Tuning
net.core.rmem_max=2500000
net.core.wmem_max=2500000
```

## Troubleshooting

### Common Issues
1. Node not starting
   - Check service status
   - Verify permissions
   - Review logs
   - Check disk space
   - Verify network connectivity

2. Backup failures
   - Check disk space
   - Verify file permissions
   - Check network connection
   - Review error logs

3. Installation issues
   - Verify Ubuntu version (20.04 or 22.04)
   - Check system requirements
   - Review installation logs
   - Verify network connectivity

### Debug Commands
```bash
# Check node status
sudo systemctl status avalanchego

# View error logs
sudo journalctl -u avalanchego -p err

# Verify network
curl -X POST --data '{
    "jsonrpc":"2.0",
    "id"     :1,
    "method" :"info.isBootstrapped",
    "params": {"chain": "P"}
}' -H 'content-type:application/json;' 127.0.0.1:9650/ext/info
```

## Support

For issues and feature requests:
- Open an issue in the repository
- Include:
  - Script version
  - Node type
  - Error messages
  - Relevant logs
  - Steps to reproduce
