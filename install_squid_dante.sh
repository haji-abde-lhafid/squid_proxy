#!/bin/bash

# Universal Proxy Server Installation Script (HTTP + SOCKS5)
# Installs: Squid (HTTP/HTTPS) and Dante (SOCKS5)
# Works on: CentOS, RHEL, Fedora, Ubuntu, Debian, Alpine, Amazon Linux, AlmaLinux
# Usage: sudo bash install_squid_dante.sh [--all-ips]
#   --all-ips    : Bind proxy to all public IPs on the server

set -e  # Exit on any error

# Configuration
PROXY_USER="rooot"
PROXY_PASSWORD="aaaa5555"
HTTP_PORT="8888"
SOCKS_PORT="1080"
ALL_IPS_MODE=false

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
    echo -e "\e[32m✅ $1\e[0m"
}

print_error() {
    echo -e "\e[31m❌ $1\e[0m"
}

print_warning() {
    echo -e "\e[33m⚠️  $1\e[0m"
}

print_info() {
    echo -e "\e[34mℹ️  $1\e[0m"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all-ips|-a)
                ALL_IPS_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: sudo bash $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --all-ips, -a    Bind proxy to all public IPs on the server"
                echo "  --help, -h       Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Get all public IPs on the server
get_all_public_ips() {
    local ips=()
    
    # Method 1: Get IPs from ip command (most reliable)
    if command -v ip &> /dev/null; then
        while IFS= read -r ip; do
            # Filter out localhost and private IPs
            if [[ ! "$ip" =~ ^127\. ]] && [[ ! "$ip" =~ ^10\. ]] && \
               [[ ! "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && \
               [[ ! "$ip" =~ ^192\.168\. ]]; then
                ips+=("$ip")
            fi
        done < <(ip -4 addr show | grep -oP 'inet \K[\d.]+' 2>/dev/null)
    fi
    
    # Method 2: Get IPs from hostname command
    if [ ${#ips[@]} -eq 0 ] && command -v hostname &> /dev/null; then
        while IFS= read -r ip; do
            if [[ ! "$ip" =~ ^127\. ]] && [[ ! "$ip" =~ ^10\. ]] && \
               [[ ! "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && \
               [[ ! "$ip" =~ ^192\.168\. ]]; then
                ips+=("$ip")
            fi
        done < <(hostname -I 2>/dev/null | tr ' ' '\n')
    fi
    
    # Method 3: Try to get external IP
    if [ ${#ips[@]} -eq 0 ]; then
        local ext_ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null)
        if [ -n "$ext_ip" ] && [[ ! "$ext_ip" =~ ^127\. ]]; then
            ips+=("$ext_ip")
        fi
    fi
    
    # If still no IPs found, get any non-localhost IP
    if [ ${#ips[@]} -eq 0 ]; then
        while IFS= read -r ip; do
            if [[ ! "$ip" =~ ^127\. ]]; then
                ips+=("$ip")
            fi
        done < <(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' || hostname -I 2>/dev/null | tr ' ' '\n')
    fi
    
    # Remove duplicates and return
    printf '%s\n' "${ips[@]}" | sort -u
}

# Detect default interface
# Detect default interface
get_default_interface() {
    ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' | head -n1
}

# Install Packages
install_packages() {
    case $OS in
        ubuntu|debian)
            print_info "Installing packages on Ubuntu/Debian..."
            apt-get update
            apt-get install -y squid apache2-utils dante-server
            ;;
        centos|rhel|fedora|amzn|almalinux)
            print_info "Installing packages on CentOS/RHEL/Fedora/Amazon Linux/AlmaLinux..."
            if command -v dnf &> /dev/null; then
                dnf install -y epel-release || true
                dnf install -y squid httpd-tools dante-server
            else
                yum install -y epel-release || true
                yum install -y squid httpd-tools dante-server
            fi
            ;;
        alpine)
            print_info "Installing packages on Alpine Linux..."
            apk update
            apk add squid apache2-utils dante-server
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Fix authentication helper paths for Squid
fix_squid_auth_paths() {
    print_info "Fixing Squid authentication helper paths..."
    
    # Find the actual location of basic_ncsa_auth
    local auth_paths=$(find /usr -name "basic_ncsa_auth" 2>/dev/null | head -1)
    
    if [ -n "$auth_paths" ]; then
        print_status "Found basic_ncsa_auth at: $auth_paths"
        
        # Create directories if they don't exist
        mkdir -p /usr/lib/squid
        mkdir -p /usr/lib64/squid
        
        # Create symbolic links to ensure both paths work
        ln -sf "$auth_paths" /usr/lib/squid/basic_ncsa_auth 2>/dev/null || true
        ln -sf "$auth_paths" /usr/lib64/squid/basic_ncsa_auth 2>/dev/null || true
    fi
}

# Create System User for Authentication (required for Dante, used for Squid too)
create_system_user() {
    print_info "Creating system user for proxy authentication..."
    
    if id "$PROXY_USER" &>/dev/null; then
        print_warning "User $PROXY_USER already exists. Updating password..."
    else
        useradd -r -M -s /sbin/nologin "$PROXY_USER" 2>/dev/null || adduser -S -D -H -s /sbin/nologin "$PROXY_USER" 2>/dev/null
    fi
    
    echo "$PROXY_USER:$PROXY_PASSWORD" | chpasswd
    print_status "User $PROXY_USER created/updated successfully"
}

# Configure Squid
configure_squid() {
    print_info "Creating Squid configuration..."
    
    # Find the actual auth path
    local auth_path=$(find /usr -name "basic_ncsa_auth" 2>/dev/null | head -1)
    if [ -z "$auth_path" ]; then auth_path="/usr/lib64/squid/basic_ncsa_auth"; fi
    
    # Configure http_port
    local http_port_config=""
    if [ "$ALL_IPS_MODE" = true ] && [ ${#ALL_PUBLIC_IPS[@]} -gt 0 ]; then
        for ip in "${ALL_PUBLIC_IPS[@]}"; do
            http_port_config="${http_port_config}http_port ${ip}:${HTTP_PORT}"$'\n'
        done
    else
        http_port_config="http_port ${HTTP_PORT}"
    fi
    
    cat > /etc/squid/squid.conf << EOF
# Squid Proxy Configuration
${http_port_config}
visible_hostname $(hostname -f 2>/dev/null || echo "squid-proxy")
dns_v4_first on
follow_x_forwarded_for deny all

# Authentication
auth_param basic program $auth_path /etc/squid/passwords
auth_param basic realm "Squid Proxy Server"
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

acl authenticated proxy_auth REQUIRED
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

http_access allow CONNECT authenticated SSL_ports
http_access allow authenticated
http_access deny all

forwarded_for delete
via off
request_header_access Via deny all
request_header_access X-Forwarded-For deny all

maximum_object_size 256 MB
cache_dir ufs /var/spool/squid 1000 16 256
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOF

    # Create password file for Squid
    htpasswd -b -c /etc/squid/passwords "$PROXY_USER" "$PROXY_PASSWORD" 2>/dev/null || \
    printf "$PROXY_USER:$(openssl passwd -crypt $PROXY_PASSWORD)\n" > /etc/squid/passwords
    
    chmod 600 /etc/squid/passwords
    chown squid:squid /etc/squid/passwords 2>/dev/null || chown proxy:proxy /etc/squid/passwords 2>/dev/null || true
    
    # Initialize cache
    squid -z 2>/dev/null || true
    print_status "Squid configuration created"
}

# Configure Dante (SOCKS5)
configure_dante() {
    print_info "Creating Dante (SOCKS5) configuration..."
    
    # Determine config file path
    local dante_conf="/etc/danted.conf"
    if [ -f /etc/sockd.conf ] || [ "$OS" == "centos" ] || [ "$OS" == "rhel" ] || [ "$OS" == "alpine" ]; then
        dante_conf="/etc/sockd.conf"
    fi
    
    local iface=$(get_default_interface)
    if [ -z "$iface" ]; then iface="eth0"; fi
    
    cat > "$dante_conf" << EOF
logoutput: syslog stdout /var/log/sockd.log

# Server address
internal: 0.0.0.0 port = ${SOCKS_PORT}
external: ${iface}

# User authentication
socksmethod: username
clientmethod: none
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error connect disconnect
    socksmethod: username
}
EOF
    print_status "Dante configuration created at $dante_conf"
}

# Configure firewall
configure_firewall() {
    print_info "Configuring firewall for ports ${HTTP_PORT} (HTTP) and ${SOCKS_PORT} (SOCKS)..."
    
    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
                ufw allow $HTTP_PORT/tcp
                ufw allow $SOCKS_PORT/tcp
                ufw allow $SOCKS_PORT/udp
                print_status "UFW configured"
            fi
            ;;
        centos|rhel|fedora|amzn|almalinux)
            if systemctl is-active --quiet firewalld; then
                firewall-cmd --permanent --add-port=${HTTP_PORT}/tcp
                firewall-cmd --permanent --add-port=${SOCKS_PORT}/tcp
                firewall-cmd --permanent --add-port=${SOCKS_PORT}/udp
                firewall-cmd --reload
                print_status "Firewalld configured"
            fi
            ;;
        alpine)
            if command -v iptables &> /dev/null; then
                iptables -A INPUT -p tcp --dport $HTTP_PORT -j ACCEPT
                iptables -A INPUT -p tcp --dport $SOCKS_PORT -j ACCEPT
                iptables -A INPUT -p udp --dport $SOCKS_PORT -j ACCEPT
                print_status "iptables configured"
            fi
            ;;
    esac
}

# Start Services
start_services() {
    print_info "Starting services..."
    
    # Restart Squid
    if systemctl --version &> /dev/null; then
        systemctl enable squid
        systemctl restart squid
        
        # Determine Dante service name
        if systemctl list-unit-files | grep -q danted.service; then
            systemctl enable danted
            systemctl restart danted
        elif systemctl list-unit-files | grep -q sockd.service; then
            systemctl enable sockd
            systemctl restart sockd
        else
            # Fallback try
            systemctl enable danted 2>/dev/null || systemctl enable sockd 2>/dev/null
            systemctl restart danted 2>/dev/null || systemctl restart sockd 2>/dev/null
        fi
        
    elif [ -x /etc/init.d/squid ]; then
        service squid restart
        service danted restart 2>/dev/null || service sockd restart 2>/dev/null
    else
        # Alpine / OpenRC
        rc-update add squid
        rc-service squid restart
        
        if rc-service -l | grep -q dante; then
             rc-update add dante
             rc-service dante restart
        elif rc-service -l | grep -q sockd; then
             rc-update add sockd
             rc-service sockd restart
        else
             # Try blind
             rc-update add sockd 2>/dev/null
             rc-service sockd restart 2>/dev/null
        fi
    fi
    
    print_status "Services restarted"
}

main() {
    parse_args "$@"
    
    echo "=================================================="
    echo "🔧 Universal Proxy Installer (HTTP + SOCKS5)"
    echo "=================================================="
    
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root: sudo bash $0"
        exit 1
    fi

    detect_os
    print_info "Detected OS: $OS $OS_VERSION"
    
    # Get IP
    ALL_PUBLIC_IPS=()
    if [ "$ALL_IPS_MODE" = true ]; then
        ALL_PUBLIC_IPS_STR=$(get_all_public_ips)
        if [ -z "$ALL_PUBLIC_IPS_STR" ]; then
             ALL_PUBLIC_IPS_STR=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")
        fi
        while IFS= read -r ip; do
            [ -n "$ip" ] && ALL_PUBLIC_IPS+=("$ip")
        done <<< "$ALL_PUBLIC_IPS_STR"
        SERVER_IP="${ALL_PUBLIC_IPS[0]}"
    else
        SERVER_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}' || head -1)
        ALL_PUBLIC_IPS=("$SERVER_IP")
    fi

    install_packages
    create_system_user   # For Dante (and synced for Squid)
    fix_squid_auth_paths
    configure_squid
    configure_dante
    configure_firewall
    start_services

    echo ""
    echo "=================================================="
    echo "🎉 Proxy Installation Complete!"
    echo "=================================================="
    echo "User: $PROXY_USER"
    echo "Pass: $PROXY_PASSWORD"
    echo "Server IP: $SERVER_IP"
    echo ""
    echo "📡 HTTP Proxy (Squid):"
    echo "   Port: $HTTP_PORT"
    echo "   URL: http://$PROXY_USER:$PROXY_PASSWORD@$SERVER_IP:$HTTP_PORT"
    echo ""
    echo "🧦 SOCKS5 Proxy (Dante):"
    echo "   Port: $SOCKS_PORT"
    echo "   URL: socks5://$PROXY_USER:$PROXY_PASSWORD@$SERVER_IP:$SOCKS_PORT"
    echo ""
    if [ "$ALL_IPS_MODE" = true ]; then
        echo "ℹ️  Bound to ${#ALL_PUBLIC_IPS[@]} IPs. You can use any of them."
    fi
    echo "=================================================="
}

main "$@"
