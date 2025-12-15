#!/bin/bash

# Universal Squid Proxy Installation Script with Auth Fix
# Works on: CentOS, RHEL, Fedora, Ubuntu, Debian, Alpine, Amazon Linux, AlmaLinux
# Usage: sudo bash install_squid_proxy.sh [--all-ips]
#   --all-ips    : Bind proxy to all public IPs on the server

set -e  # Exit on any error

# Configuration
PROXY_USER="rooot"
PROXY_PASSWORD="aaaa5555"
PROXY_PORT="8888"
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

# Install Squid based on OS
install_squid() {
    case $OS in
        ubuntu|debian)
            print_info "Installing Squid on Ubuntu/Debian..."
            apt-get update
            apt-get install -y squid apache2-utils
            ;;
        centos|rhel|fedora|amzn|almalinux)
            print_info "Installing Squid on CentOS/RHEL/Fedora/Amazon Linux/AlmaLinux..."
            if command -v dnf &> /dev/null; then
                dnf install -y squid httpd-tools
            else
                yum install -y squid httpd-tools
            fi
            ;;
        alpine)
            print_info "Installing Squid on Alpine Linux..."
            apk update
            apk add squid apache2-utils
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Fix authentication helper paths
fix_auth_paths() {
    print_info "Fixing authentication helper paths..."
    
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
        
        print_status "Created symbolic links for authentication helper"
    else
        print_warning "basic_ncsa_auth not found, trying to install helpers..."
        
        # Try to install helper packages
        case $OS in
            ubuntu|debian)
                apt-get install -y squid-langpack 2>/dev/null || true
                ;;
            centos|rhel|fedora|amzn|almalinux)
                if command -v dnf &> /dev/null; then
                    dnf install -y squid-helpers 2>/dev/null || true
                else
                    yum install -y squid-helpers 2>/dev/null || true
                fi
                ;;
        esac
        
        # Search again after installation
        auth_paths=$(find /usr -name "basic_ncsa_auth" 2>/dev/null | head -1)
        if [ -n "$auth_paths" ]; then
            mkdir -p /usr/lib/squid
            mkdir -p /usr/lib64/squid
            ln -sf "$auth_paths" /usr/lib/squid/basic_ncsa_auth
            ln -sf "$auth_paths" /usr/lib64/squid/basic_ncsa_auth
            print_status "Fixed authentication helper paths after package installation"
        else
            print_warning "Could not find basic_ncsa_auth, using fallback configuration"
        fi
    fi
}

# Create Squid configuration with dynamic auth path
create_squid_config() {
    print_info "Creating Squid configuration..."
    
    # Find the actual auth path
    local auth_path=$(find /usr -name "basic_ncsa_auth" 2>/dev/null | head -1)
    
    if [ -z "$auth_path" ]; then
        # Fallback: use common paths
        auth_path="/usr/lib64/squid/basic_ncsa_auth"
    fi
    
    # Configure http_port based on mode
    local http_port_config
    if [ "$ALL_IPS_MODE" = true ]; then
        # Bind to all interfaces (0.0.0.0)
        http_port_config="http_port 0.0.0.0:${PROXY_PORT}"
        print_info "Configuring Squid to listen on all interfaces (all public IPs)"
    else
        # Default: bind to all interfaces (Squid default behavior)
        http_port_config="http_port ${PROXY_PORT}"
    fi
    
    cat > /etc/squid/squid.conf << EOF
# Squid Proxy Configuration
# Generated by universal installation script

${http_port_config}
visible_hostname squid-proxy
dns_v4_first on

# Authentication with dynamic path
auth_param basic program $auth_path /etc/squid/passwords
auth_param basic realm "Squid Proxy Server"
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off

# ACL Definitions
acl authenticated proxy_auth REQUIRED
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

# Access Control
http_access allow CONNECT authenticated SSL_ports
http_access allow authenticated
http_access deny all

# Security Settings
forwarded_for delete
via off
request_header_access Via deny all
request_header_access X-Forwarded-For deny all

# Performance Settings
maximum_object_size 256 MB
cache_dir ufs /var/spool/squid 1000 16 256

# Logging
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
EOF

    print_status "Squid configuration created with auth path: $auth_path"
}

# Configure firewall based on OS
configure_firewall() {
    case $OS in
        ubuntu|debian)
            if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
                ufw allow $PROXY_PORT/tcp
                print_status "UFW configured"
            fi
            ;;
        centos|rhel|fedora|amzn|almalinux)
            if systemctl is-active --quiet firewalld; then
                firewall-cmd --permanent --add-port=${PROXY_PORT}/tcp
                firewall-cmd --reload
                print_status "Firewalld configured"
            fi
            ;;
        alpine)
            if command -v iptables &> /dev/null; then
                iptables -A INPUT -p tcp --dport $PROXY_PORT -j ACCEPT
                print_status "iptables configured"
            fi
            ;;
    esac
}

# Get service management command
get_service_cmd() {
    if systemctl --version &> /dev/null; then
        echo "systemctl"
    elif [ -x /etc/init.d/squid ]; then
        echo "service"
    else
        echo "rc-service"
    fi
}

# Main installation function
main() {
    # Parse command line arguments
    parse_args "$@"
    
    echo "=================================================="
    echo "🔧 Universal Squid Proxy Installation Script"
    echo "🔧 WITH AUTHENTICATION PATH FIX"
    echo "=================================================="
    echo "Username: $PROXY_USER"
    echo "Password: $PROXY_PASSWORD"
    echo "Port: $PROXY_PORT"
    if [ "$ALL_IPS_MODE" = true ]; then
        echo "Mode: All Public IPs (binding to all interfaces)"
    fi
    echo "=================================================="

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root: sudo bash $0"
        exit 1
    fi

    # Detect OS
    detect_os
    print_info "Detected OS: $OS $OS_VERSION"

    # Get server IP(s)
    ALL_PUBLIC_IPS=()  # Initialize array
    if [ "$ALL_IPS_MODE" = true ]; then
        print_info "Detecting all public IPs on the server..."
        ALL_PUBLIC_IPS_STR=$(get_all_public_ips)
        if [ -z "$ALL_PUBLIC_IPS_STR" ]; then
            print_warning "No public IPs detected, using fallback method"
            ALL_PUBLIC_IPS_STR=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")
        fi
        # Convert to array
        while IFS= read -r ip; do
            [ -n "$ip" ] && ALL_PUBLIC_IPS+=("$ip")
        done <<< "$ALL_PUBLIC_IPS_STR"
        SERVER_IP="${ALL_PUBLIC_IPS[0]}"
        print_info "Detected ${#ALL_PUBLIC_IPS[@]} public IP(s):"
        for ip in "${ALL_PUBLIC_IPS[@]}"; do
            echo "   - $ip"
        done
    else
        SERVER_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}' || ip addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
        print_info "Server IP: $SERVER_IP"
        # Set single IP in array for consistent output handling
        ALL_PUBLIC_IPS=("$SERVER_IP")
    fi

    # Update system
    print_info "Updating system packages..."
    case $OS in
        ubuntu|debian) apt-get update ;;
        centos|rhel|fedora|amzn|almalinux) 
            if command -v dnf &> /dev/null; then dnf update -y; else yum update -y; fi 
            ;;
        alpine) apk update ;;
    esac

    # Install Squid
    install_squid

    # Fix authentication paths BEFORE creating config
    fix_auth_paths

    # Create backup of original config
    cp /etc/squid/squid.conf /etc/squid/squid.conf.backup 2>/dev/null || true

    # Create configuration with correct auth path
    create_squid_config

    # Create password file
    print_info "Setting up authentication..."
    case $OS in
        alpine)
            htpasswd -b -c /etc/squid/passwords "$PROXY_USER" "$PROXY_PASSWORD" 2>/dev/null || \
            printf "$PROXY_USER:$(openssl passwd -crypt $PROXY_PASSWORD)\n" > /etc/squid/passwords
            ;;
        *)
            htpasswd -b -c /etc/squid/passwords "$PROXY_USER" "$PROXY_PASSWORD" || \
            printf "$PROXY_USER:$(openssl passwd -crypt $PROXY_PASSWORD)\n" > /etc/squid/passwords
            ;;
    esac

    # Set proper permissions
    chown squid:squid /etc/squid/passwords 2>/dev/null || chown proxy:proxy /etc/squid/passwords 2>/dev/null || true
    chmod 600 /etc/squid/passwords

    # Create cache directory if it doesn't exist
    mkdir -p /var/spool/squid
    chown squid:squid /var/spool/squid 2>/dev/null || chown proxy:proxy /var/spool/squid 2>/dev/null || true

    # Initialize cache directory
    print_info "Initializing cache directory..."
    squid -z 2>/dev/null || true

    # Configure firewall
    configure_firewall

    # Start and enable Squid service
    print_info "Starting Squid service..."
    SERVICE_CMD=$(get_service_cmd)
    
    case $SERVICE_CMD in
        systemctl)
            systemctl enable squid
            systemctl start squid
            sleep 3
            if systemctl is-active --quiet squid; then
                print_status "Squid is running"
            else
                print_error "Squid failed to start"
                systemctl status squid
                exit 1
            fi
            ;;
        service)
            service squid enable
            service squid start
            sleep 3
            if service squid status | grep -q "running"; then
                print_status "Squid is running"
            else
                print_error "Squid failed to start"
                service squid status
                exit 1
            fi
            ;;
        rc-service)
            rc-update add squid
            rc-service squid start
            sleep 3
            if rc-service squid status | grep -q "started"; then
                print_status "Squid is running"
            else
                print_error "Squid failed to start"
                rc-service squid status
                exit 1
            fi
            ;;
    esac

    # Test the proxy
    print_info "Testing proxy connection..."
    if command -v curl &> /dev/null; then
        TEST_RESULT=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -x http://${PROXY_USER}:${PROXY_PASSWORD}@localhost:${PROXY_PORT} http://httpbin.org/ip || echo "FAILED")
        
        if [ "$TEST_RESULT" = "200" ]; then
            print_status "Proxy test successful"
        else
            print_warning "Proxy test returned HTTP $TEST_RESULT - checking service..."
        fi
    else
        print_warning "curl not available, skipping proxy test"
    fi

    # Display installation summary
    echo ""
    echo "=================================================="
    echo "🎉 Squid Proxy Installation Complete!"
    echo "=================================================="
    echo "🔧 Proxy Details:"
    echo "   OS: $OS $OS_VERSION"
    if [ "$ALL_IPS_MODE" = true ]; then
        echo "   Mode: All Public IPs (listening on all interfaces)"
        echo "   Detected Public IPs: ${#ALL_PUBLIC_IPS[@]}"
        for ip in "${ALL_PUBLIC_IPS[@]}"; do
            echo "      - $ip"
        done
    else
        echo "   Server IP: $SERVER_IP"
    fi
    echo "   Port: $PROXY_PORT"
    echo "   Username: $PROXY_USER"
    echo "   Password: $PROXY_PASSWORD"
    echo ""
    echo "🔗 Proxy URLs:"
    if [ "$ALL_IPS_MODE" = true ]; then
        for ip in "${ALL_PUBLIC_IPS[@]}"; do
            echo "   http://${PROXY_USER}:${PROXY_PASSWORD}@${ip}:${PROXY_PORT}"
        done
    else
        echo "   http://${PROXY_USER}:${PROXY_PASSWORD}@${SERVER_IP}:${PROXY_PORT}"
    fi
    echo ""
    echo "🔧 Authentication Fix Applied:"
    echo "   ✅ Symbolic links created for basic_ncsa_auth"
    echo "   ✅ Configuration uses dynamic auth path"
    if [ "$ALL_IPS_MODE" = true ]; then
        echo "   ✅ Proxy configured to listen on all public IPs"
    fi
    echo ""
    echo "📝 Usage Examples:"
    if [ "$ALL_IPS_MODE" = true ]; then
        echo "   curl -x http://${PROXY_USER}:${PROXY_PASSWORD}@${ALL_PUBLIC_IPS[0]}:${PROXY_PORT} http://example.com"
    else
        echo "   curl -x http://${PROXY_USER}:${PROXY_PASSWORD}@${SERVER_IP}:${PROXY_PORT} http://example.com"
    fi
    echo ""
    echo "🛠️  Management Commands:"
    echo "   Service management: $SERVICE_CMD [start|stop|restart|status] squid"
    echo "   View logs: tail -f /var/log/squid/access.log"
    echo "   Test proxy: curl -x http://${PROXY_USER}:${PROXY_PASSWORD}@localhost:${PROXY_PORT} http://httpbin.org/ip"
    echo "=================================================="
}

# Run main function
main "$@"