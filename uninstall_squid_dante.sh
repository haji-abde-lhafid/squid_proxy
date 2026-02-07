#!/bin/bash

# Uninstall Squid & Dante Proxy Script
# Removes: Squid, Dante, Configs, Logs, and Proxy User
# Usage: sudo bash uninstall_squid_dante.sh

set -e

# Configuration (Must match install script)
PROXY_USER="rooot"
HTTP_PORT="8888"
SOCKS_PORT="1080"

# Colors
print_status() { echo -e "\e[32m✅ $1\e[0m"; }
print_error() { echo -e "\e[31m❌ $1\e[0m"; }
print_warning() { echo -e "\e[33m⚠️  $1\e[0m"; }
print_info() { echo -e "\e[34mℹ️  $1\e[0m"; }

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
}

# Stop Services
stop_services() {
    print_info "Stopping services..."
    if systemctl --version &> /dev/null; then
        systemctl stop squid || true
        systemctl disable squid || true
        
        systemctl stop danted || true
        systemctl disable danted || true
        
        systemctl stop sockd || true
        systemctl disable sockd || true
    elif [ -x /etc/init.d/squid ]; then
        service squid stop || true
        service danted stop || true
        service sockd stop || true
    else
        rc-service squid stop || true
        rc-service dante stop || true
        rc-service sockd stop || true
        
        rc-update del squid || true
        rc-update del dante || true
        rc-update del sockd || true
    fi
}

# Remove Packages
remove_packages() {
    print_info "Removing packages..."
    case $OS in
        ubuntu|debian)
            apt-get remove --purge -y squid apache2-utils dante-server || true
            apt-get autoremove -y || true
            ;;
        centos|rhel|fedora|amzn|almalinux)
            if command -v dnf &> /dev/null; then
                dnf remove -y squid httpd-tools dante-server || true
            else
                yum remove -y squid httpd-tools dante-server || true
            fi
            ;;
        alpine)
            apk del squid apache2-utils dante-server || true
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Remove Configs and Logs
remove_files() {
    print_info "Removing configuration files and logs..."
    rm -rf /etc/squid
    rm -f /etc/danted.conf
    rm -f /etc/sockd.conf
    rm -rf /var/log/squid
    rm -f /var/log/sockd.log
    rm -rf /var/spool/squid
    
    # Remove auth helper symlinks created by install script
    rm -f /usr/lib/squid/basic_ncsa_auth
    rm -f /usr/lib64/squid/basic_ncsa_auth
}

# Remove User
remove_user() {
    if id "$PROXY_USER" &>/dev/null; then
        print_warning "Removing proxy user: $PROXY_USER"
        userdel "$PROXY_USER" || deluser "$PROXY_USER" || true
    else
        print_info "User $PROXY_USER not found, skipping removal."
    fi
}

# Remove Firewall Rules
remove_firewall() {
    print_info "Cleaning up firewall rules..."
    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null; then
                ufw delete allow $HTTP_PORT/tcp || true
                ufw delete allow $SOCKS_PORT/tcp || true
                ufw delete allow $SOCKS_PORT/udp || true
            fi
            ;;
        centos|rhel|fedora|amzn|almalinux)
            if command -v firewall-cmd &> /dev/null; then
                firewall-cmd --permanent --remove-port=${HTTP_PORT}/tcp || true
                firewall-cmd --permanent --remove-port=${SOCKS_PORT}/tcp || true
                firewall-cmd --permanent --remove-port=${SOCKS_PORT}/udp || true
                firewall-cmd --reload
            fi
            ;;
        alpine)
            # iptables cleanup is tricky without flushing everything, skipping to avoid breaking other rules
            print_warning "Skipping iptables cleanup on Alpine to avoid affecting other services."
            ;;
    esac
}

main() {
    echo "=================================================="
    echo "🗑️  Squid & Dante Uninstaller"
    echo "=================================================="
    
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root: sudo bash $0"
        exit 1
    fi

    detect_os
    stop_services
    remove_packages
    remove_files
    remove_user
    remove_firewall

    echo ""
    echo "=================================================="
    echo "✅ Uninstallation Complete!"
    echo "=================================================="
}

main
