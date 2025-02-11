# Avalanche Node Management Script

A comprehensive management script for Avalanche nodes on Ubuntu Server, providing full lifecycle management including deployment, migration, backup, and restore functionality.

## Table of Contents
1. [Features](#features)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Node Types](#node-types)
5. [Security Guide](#security-guide)
6. [Backup & Recovery](#backup--recovery)
7. [Monitoring](#monitoring)
8. [Operations Guide](#operations-guide)
9. [Technical Specifications](#technical-specifications)
10. [Troubleshooting](#troubleshooting)
11. [Support](#support)

## Features

### Core Features
- Automated installation and configuration
- Multiple node type support (Validator, API, Archive)
- Secure deployment with hardened defaults
- Automatic version management
- Performance optimization
- Comprehensive backup solutions with GitHub integration
- Monitoring integration with Prometheus and Grafana
- Migration support with automatic state preservation
- Automatic node detection and configuration

### Installation and Migration
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

- **GitHub Integration**
  - Private repository backup
  - Version-controlled history
  - Automated daily backups
  - Easy restoration process
  - Token-based authentication
  - Commit signing support

### BLS Key Management
- Unified key operations
- Automated backup before operations
- Secure key generation
- Version compatibility checks
- Key rotation support
- Integrity verification

### Performance Monitoring
- Real-time metrics collection
- Custom Grafana dashboards
- Alert configuration
- Resource usage tracking
- Network performance monitoring
- Blockchain metrics visualization

## Prerequisites

### System Requirements
- Ubuntu Server 20.04 LTS or 22.04 LTS
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
- Optional Ports:
  - 9090/tcp: Prometheus
  - 3000/tcp: Grafana

### GitHub Backup Prerequisites
- Private GitHub repository
- Personal Access Token with repo scope
- Git installed on node
- Valid GitHub email for commits
- Sufficient repository storage

## Quick Start

### Fresh Installation
```bash
# Download
wget -O avalanche-deploy.sh https://raw.githubusercontent.com/ava-labs/avalanche-node-deployment/main/avalanche-deploy.sh

# Make executable
chmod +x avalanche-deploy.sh

# Run
sudo ./avalanche-deploy.sh
```

### GitHub Backup Setup
```bash
# During script execution, select:
# 1. Backup Operations
# 2. Configure GitHub backup
# 3. Follow prompts for:
#    - Repository details (username/repo)
#    - Personal Access Token
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
- Secure token storage
- Access control enforcement
- Automated cleanup
- Backup verification
- Repository privacy enforcement
- Token rotation support

### Monitoring Security
- HTTPS enabled endpoints
- Certificate management
- Access restrictions
- Regular auditing
- Secure dashboards
- Rate limiting

## Backup & Recovery

### Critical Files
Located in `/home/avalanche/.avalanchego/staking/`:
- `staker.crt`: Node certificate
- `staker.key`: Node private key
- `signer.key`: BLS key
- `.avalanchego/config.json`: Node configuration
- `.avalanchego/github_backup.conf`: GitHub backup configuration

### Backup Methods

#### GitHub Backup
```bash
# First-time Setup
1. Select "Configure GitHub backup" from backup menu
2. Enter repository details (username/repo)
3. Provide Personal Access Token
4. Configure automated backups (optional)

# Manual Backup
Select "Perform GitHub backup" from backup menu

# Automated Backup
Enabled during configuration (daily backups)

# Restore
1. Select "Restore from GitHub backup" from backup menu
2. Choose backup timestamp
3. Automatic backup of current files
4. Verification of restored files
```

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

### Monitoring
- Prometheus metrics collection
- Grafana dashboards
- System metrics monitoring
- Performance tracking
- Alert configuration

### Maintenance
- Automated updates
- Performance optimization
- Log rotation
- Backup verification
- Security auditing

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
   - Verify GitHub token validity
   - Check repository access
   - Ensure sufficient space
   - Verify network connection
   - Check file permissions

3. Migration issues
   - Backup current deployment
   - Verify file permissions
   - Check service configuration
   - Ensure sufficient resources
   - Verify network stability

4. Monitoring issues
   - Check service status
   - Verify port accessibility
   - Review certificate validity
   - Check disk space
   - Verify metrics collection

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
