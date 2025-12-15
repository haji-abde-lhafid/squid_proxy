# Universal Squid Proxy Installation Script

A comprehensive bash script for installing and configuring Squid Proxy with authentication support on multiple Linux distributions.

## Features

- ✅ **Universal Support**: Works on CentOS, RHEL, Fedora, Ubuntu, Debian, Alpine, Amazon Linux, and AlmaLinux
- ✅ **Authentication**: Built-in username/password authentication
- ✅ **All IPs Support**: Option to bind proxy to all public IPs on the server
- ✅ **Automatic Path Fix**: Automatically fixes authentication helper paths
- ✅ **Firewall Configuration**: Automatically configures firewall rules
- ✅ **Service Management**: Handles service startup and enables auto-start

## Supported Operating Systems

- **Red Hat Family**: CentOS, RHEL, Fedora, AlmaLinux
- **Debian Family**: Ubuntu, Debian
- **Other**: Alpine Linux, Amazon Linux

## Prerequisites

- Root or sudo access
- Internet connection for package installation
- Bash shell

## Installation

### Basic Installation (Single IP)

```bash
sudo bash install_squid_proxy.sh
```

This will install Squid Proxy with default settings:
- Username: `rooot`
- Password: `aaaa5555`
- Port: `8888`
- Binds to default interface

### Installation on All Public IPs

To install the proxy and bind it to all public IPs on your server:

```bash
sudo bash install_squid_proxy.sh --all-ips
```

or using the short form:

```bash
sudo bash install_squid_proxy.sh -a
```

When using `--all-ips`, the script will:
- Detect all public IPs on the server
- Configure Squid to listen on all interfaces (0.0.0.0)
- Display proxy URLs for each detected IP

## Command-Line Options

| Option | Short Form | Description |
|--------|------------|-------------|
| `--all-ips` | `-a` | Bind proxy to all public IPs on the server |
| `--help` | `-h` | Display help message |

## Default Configuration

The script uses the following default values (can be modified in the script):

- **Username**: `rooot`
- **Password**: `aaaa5555`
- **Port**: `8888`

To change these defaults, edit the configuration section at the top of the script:

```bash
PROXY_USER="rooot"
PROXY_PASSWORD="aaaa5555"
PROXY_PORT="8888"
```

## What the Script Does

1. **OS Detection**: Automatically detects your operating system
2. **System Update**: Updates system packages
3. **Squid Installation**: Installs Squid and required dependencies
4. **Path Fix**: Automatically fixes authentication helper paths
5. **Configuration**: Creates optimized Squid configuration
6. **Authentication Setup**: Creates password file with credentials
7. **Firewall Configuration**: Opens the proxy port in firewall
8. **Service Start**: Starts and enables Squid service
9. **Testing**: Tests the proxy connection

## Usage Examples

### Test the Proxy

```bash
curl -x http://rooot:aaaa5555@YOUR_SERVER_IP:8888 http://httpbin.org/ip
```

### Use with wget

```bash
wget --proxy=on --http-proxy=http://rooot:aaaa5555@YOUR_SERVER_IP:8888 http://example.com
```

### Use in Browser

Configure your browser to use:
- **Proxy Type**: HTTP
- **Host**: YOUR_SERVER_IP
- **Port**: 8888
- **Username**: rooot
- **Password**: aaaa5555

## Management Commands

### Service Management

```bash
# Start Squid
sudo systemctl start squid

# Stop Squid
sudo systemctl stop squid

# Restart Squid
sudo systemctl restart squid

# Check Status
sudo systemctl status squid

# Enable Auto-start
sudo systemctl enable squid
```

### View Logs

```bash
# Access log
tail -f /var/log/squid/access.log

# Cache log
tail -f /var/log/squid/cache.log
```

### Test Proxy Connection

```bash
curl -x http://rooot:aaaa5555@localhost:8888 http://httpbin.org/ip
```

## Configuration Files

- **Main Config**: `/etc/squid/squid.conf`
- **Backup Config**: `/etc/squid/squid.conf.backup`
- **Password File**: `/etc/squid/passwords`
- **Access Log**: `/var/log/squid/access.log`
- **Cache Log**: `/var/log/squid/cache.log`

## Adding Additional Users

To add more users to the proxy, use the `htpasswd` command:

```bash
# Add a new user (will prompt for password)
sudo htpasswd /etc/squid/passwords username

# Add a new user with password in command
sudo htpasswd -b /etc/squid/passwords username password
```

After adding users, restart Squid:

```bash
sudo systemctl restart squid
```

## Troubleshooting

### Proxy Not Starting

1. Check Squid status:
   ```bash
   sudo systemctl status squid
   ```

2. Check configuration syntax:
   ```bash
   sudo squid -k parse
   ```

3. Check logs:
   ```bash
   sudo tail -f /var/log/squid/cache.log
   ```

### Authentication Not Working

1. Verify password file exists:
   ```bash
   sudo ls -la /etc/squid/passwords
   ```

2. Check file permissions:
   ```bash
   sudo chmod 600 /etc/squid/passwords
   sudo chown squid:squid /etc/squid/passwords
   ```

3. Verify authentication helper:
   ```bash
   find /usr -name basic_ncsa_auth
   ```

### Firewall Issues

If you can't connect from outside:

1. Check firewall status:
   ```bash
   sudo firewall-cmd --list-all  # For firewalld
   sudo ufw status                # For UFW
   ```

2. Manually open port:
   ```bash
   # For firewalld
   sudo firewall-cmd --permanent --add-port=8888/tcp
   sudo firewall-cmd --reload
   
   # For UFW
   sudo ufw allow 8888/tcp
   ```

## Security Considerations

- Change default username and password immediately
- Use strong passwords
- Consider restricting access by IP in Squid configuration
- Regularly update Squid and your system
- Monitor access logs for suspicious activity

## License

This script is provided as-is for educational and practical use.

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## Related Scripts

This repository also includes:
- `add_user.sh` - Script to add users to the proxy
- `fix_squid.sh` - Script to fix common Squid issues
- `monitor.sh` - Script to monitor Squid proxy

## Support

For issues or questions, please check the script's help:

```bash
sudo bash install_squid_proxy.sh --help
```

