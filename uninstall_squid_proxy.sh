#!/bin/bash

# Squid Proxy Uninstallation Script
# Reverses changes made by install_squid_proxy.sh
# Usage: sudo bash uninstall_squid_proxy.sh

set -e  # Exit on any error

# Detect OS and architecture
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=$(cat /etc/redhat-release | sed -e 's/.*release \([0-9]\+\).*/\1/')
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        OS_VERSION=$(cat /etc/alpine-release)
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
}

# Function to print colored output
print_status() {
    echo -e "✅ $1"
}

print_error() {
    echo -e "❌ $1"
}

print_warning() {
    echo -e "⚠️  $1"
}

print_info() {
    echo -e "ℹ️  $1"
}

# Stop and disable service
stop_service() {
    print_info "Stopping Squid service..."
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet squid; then
            systemctl stop squid
            systemctl disable squid
            print_status "Stopped and disabled squid (systemctl)"
        fi
    elif [ -x /etc/init.d/squid ]; then
        service squid stop 2>/dev/null || true
        service squid disable 2>/dev/null || true
        print_status "Stopped and disabled squid (service)"
    elif command -v rc-service &> /dev/null; then
        rc-service squid stop 2>/dev/null || true
        rc-update del squid default 2>/dev/null || true
        print_status "Stopped and disabled squid (rc-service)"
    fi
}

# Remove firewall rules
remove_firewall_rules() {
    print_info "Removing firewall rules for port 8888..."
    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                ufw delete allow 8888/tcp 2>/dev/null || true
                print_status "Removed UFW rule"
            fi
            ;;
        centos|rhel|fedora|amzn|almalinux)
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --remove-port=8888/tcp 2>/dev/null || true
                firewall-cmd --reload 2>/dev/null || true
                print_status "Removed Firewalld rule"
            fi
            ;;
        alpine)
            if command -v iptables &> /dev/null; then
                # Try to delete the rule if it exists
                iptables -D INPUT -p tcp --dport 8888 -j ACCEPT 2>/dev/null || true
                print_status "Removed iptables rule (if existed)"
            fi
            ;;
    esac
}

# Cleanup files and directories
cleanup_files() {
    print_info "Cleaning up configuration and data..."
    
    # Remove config and password files
    if [ -d "/etc/squid" ]; then
        rm -rf /etc/squid
        print_status "Removed /etc/squid"
    fi
    
    # Remove logs
    if [ -d "/var/log/squid" ]; then
        rm -rf /var/log/squid
        print_status "Removed /var/log/squid"
    fi
    
    # Remove cache
    if [ -d "/var/spool/squid" ]; then
        rm -rf /var/spool/squid
        print_status "Removed /var/spool/squid"
    fi

    # Remove symlinks created by install script
    if [ -L "/usr/lib/squid/basic_ncsa_auth" ]; then
        rm /usr/lib/squid/basic_ncsa_auth
        print_status "Removed symlink /usr/lib/squid/basic_ncsa_auth"
    fi
    if [ -L "/usr/lib64/squid/basic_ncsa_auth" ]; then
        rm /usr/lib64/squid/basic_ncsa_auth
        print_status "Removed symlink /usr/lib64/squid/basic_ncsa_auth"
    fi
    
    # Try to remove wrapper directories if empty
    rmdir /usr/lib/squid 2>/dev/null || true
    rmdir /usr/lib64/squid 2>/dev/null || true
}

# Remove packages
remove_packages() {
    print_info "Uninstalling Squid packages..."
    case $OS in
        ubuntu|debian)
            apt-get install -y squid-langpack 2>/dev/null || true # Ensure dependency map is clean
            DEBIAN_FRONTEND=noninteractive apt-get purge -y squid apache2-utils squid-langpack squid-common
            apt-get autoremove -y
            ;;
        centos|rhel|fedora|amzn|almalinux)
            if command -v dnf &> /dev/null; then
                dnf remove -y squid httpd-tools squid-helpers
            else
                yum remove -y squid httpd-tools squid-helpers
            fi
            ;;
        alpine)
            apk del squid apache2-utils
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    print_status "Packages removed"
}

main() {
    echo "=================================================="
    echo "🗑️  Squid Proxy Uninstallation Script"
    echo "=================================================="

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root: sudo bash $0"
        exit 1
    fi

    detect_os
    print_info "Detected OS: $OS $OS_VERSION"

    stop_service
    remove_firewall_rules
    remove_packages
    cleanup_files

    echo ""
    echo "=================================================="
    echo "✅ Uninstallation Complete!"
    echo "=================================================="
}

main "$@"
