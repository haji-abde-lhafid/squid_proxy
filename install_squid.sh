#!/usr/bin/env bash

# ==============================================================================
# Install Squid Proxy
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true
source "$(dirname "$0")/network_utils.sh" 2>/dev/null || true
source "$(dirname "$0")/user_manager.sh" 2>/dev/null || true

generate_squid_conf() {
    local auth="$1"
    local config_file="/etc/squid/squid.conf"
    
    print_info "Generating optimized Squid configuration..."
    
    # Backup original
    if [[ -f "$config_file" && ! -f "${config_file}.orig" ]]; then
        cp "$config_file" "${config_file}.orig"
    fi
    
    cat > "$config_file" << EOF
# ============================================================
# Optimized Squid Configuration
# ============================================================

# Performance & Tuning
workers ${CPU_CORES}
max_filedescriptors 1048576
cache_mem $(( RAM_MB / 4 )) MB
maximum_object_size_in_memory 512 KB
maximum_object_size 8 MB
cache_replacement_policy heap LFUDA
memory_replacement_policy heap GDSF

# DNS
dns_nameservers 8.8.8.8 1.1.1.1 8.8.4.4
dns_v4_first on

# Logging
access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
logfile_rotate 10

# ACLs
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT

# Rules
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost manager
http_access deny manager

EOF

    if [[ "$auth" == "true" ]]; then
        # Authentication
        ensure_htpasswd
        init_passwd_file
        
        # Check htpasswd path
        local auth_param="/usr/lib/squid/basic_ncsa_auth"
        if [[ -f "/usr/lib64/squid/basic_ncsa_auth" ]]; then
            auth_param="/usr/lib64/squid/basic_ncsa_auth"
        fi
        
        cat >> "$config_file" << EOF
# Authentication Setup
auth_param basic program ${auth_param} ${PASSWD_FILE}
auth_param basic children 10 startup=5 idle=1
auth_param basic realm Proxy Authentication
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
EOF
    else
        cat >> "$config_file" << EOF
# No Authentication
http_access allow all
EOF
    fi

    # Ports
    echo "# Port Bindings" >> "$config_file"
    for ip in "${ALL_IPV4[@]}"; do
        echo "http_port ${ip}:3128" >> "$config_file"
    done
    if [[ "$HAS_IPV6" == "true" ]]; then
        echo "http_port [::0]:3128" >> "$config_file"
    fi
    
    # Refresh Patterns
    cat >> "$config_file" << EOF

# Refresh Patterns
refresh_pattern ^ftp:       1440    20%     10080
refresh_pattern ^gopher:    1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0 0%      0
refresh_pattern .           0       20%     4320

# Network Settings
forwarded_for off
request_header_access Allow allow all
request_header_access Authorization allow all
request_header_access WWW-Authenticate allow all
request_header_access Proxy-Authorization allow all
request_header_access Proxy-Authenticate allow all
request_header_access Cache-Control allow all
request_header_access Content-Encoding allow all
request_header_access Content-Length allow all
request_header_access Content-Type allow all
request_header_access Date allow all
request_header_access Expires allow all
request_header_access Host allow all
request_header_access If-Modified-Since allow all
request_header_access Last-Modified allow all
request_header_access Location allow all
request_header_access Pragma allow all
request_header_access Accept allow all
request_header_access Accept-Charset allow all
request_header_access Accept-Encoding allow all
request_header_access Accept-Language allow all
request_header_access Content-Language allow all
request_header_access Mime-Version allow all
request_header_access Retry-After allow all
request_header_access Title allow all
request_header_access Connection allow all
request_header_access Proxy-Connection allow all
request_header_access User-Agent allow all
request_header_access Cookie allow all
request_header_access All deny all
EOF
    
    print_success "Squid configuration generated."
}

install_squid() {
    local auth="${1:-true}"
    
    show_header
    print_info "Starting Squid Installation..."
    
    check_root
    check_internet
    detect_system
    detect_network
    
    disable_selinux
    optimize_sysctl
    optimize_ulimit
    
    # Install
    install_packages squid curl net-tools tar wget
    
    # Configure
    generate_squid_conf "$auth"
    
    # Firewall
    configure_firewall 3128
    
    # Service
    print_info "Restarting and enabling Squid..."
    systemctl enable squid >/dev/null 2>&1
    systemctl restart squid >/dev/null 2>&1
    
    check_result $? "Squid started successfully" "Failed to start Squid" true
    
    if [[ "$auth" == "true" ]]; then
        print_info "Setting up initial user..."
        add_user
    fi
    
    print_success "Squid installation completed!"
}

# Allow script to be run directly or sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    auth_req="true"
    if [[ "$1" == "--no-auth" ]]; then
        auth_req="false"
    fi
    install_squid "$auth_req"
fi
