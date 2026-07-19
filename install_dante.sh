#!/usr/bin/env bash

# ==============================================================================
# Install Dante Proxy
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true
source "$(dirname "$0")/network_utils.sh" 2>/dev/null || true

generate_dante_conf() {
    local auth="$1"
    local config_file="/etc/sockd.conf"
    
    print_info "Generating optimized Dante configuration..."
    
    # Backup original
    if [[ -f "$config_file" && ! -f "${config_file}.orig" ]]; then
        cp "$config_file" "${config_file}.orig"
    fi
    
    # Empty the file
    > "$config_file"
    
    # Global settings
    cat >> "$config_file" << EOF
# ============================================================
# Optimized Dante Configuration
# ============================================================

logoutput: /var/log/danted.log
user.privileged: root
user.notprivileged: nobody
timeout.io: 0

# Limits
clientmethod: none
EOF

    # Internal Interfaces (Listen)
    echo "# Internal Bindings" >> "$config_file"
    for ip in "${ALL_IPV4[@]}"; do
        echo "internal: ${ip} port = 1080" >> "$config_file"
    done
    if [[ "$HAS_IPV6" == "true" ]]; then
        echo "internal: ::0 port = 1080" >> "$config_file"
    fi

    # External Interfaces
    echo "# External Bindings" >> "$config_file"
    echo "external: ${DEFAULT_INTERFACE}" >> "$config_file"
    
    # Authentication method
    if [[ "$auth" == "true" ]]; then
        echo "socksmethod: username" >> "$config_file"
    else
        echo "socksmethod: none" >> "$config_file"
    fi
    
    # Rules
    cat >> "$config_file" << EOF

# Client Rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

EOF
    
    if [[ "$HAS_IPV6" == "true" ]]; then
        cat >> "$config_file" << EOF
client pass {
    from: ::0/0 to: ::0/0
    log: error
}
EOF
    fi

    if [[ "$auth" == "true" ]]; then
        cat >> "$config_file" << EOF
# Socks Rules - Authenticated
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF
        if [[ "$HAS_IPV6" == "true" ]]; then
            cat >> "$config_file" << EOF
socks pass {
    from: ::0/0 to: ::0/0
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF
        fi
    else
        cat >> "$config_file" << EOF
# Socks Rules - No Authentication
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
}
EOF
        if [[ "$HAS_IPV6" == "true" ]]; then
            cat >> "$config_file" << EOF
socks pass {
    from: ::0/0 to: ::0/0
    command: bind connect udpassociate
    log: error
}
EOF
        fi
    fi

    print_success "Dante configuration generated."
}

install_dante() {
    local auth="${1:-true}"
    
    show_header
    print_info "Starting Dante Installation..."
    
    check_root
    check_internet
    detect_system
    detect_network
    
    disable_selinux
    optimize_sysctl
    optimize_ulimit
    
    # Install
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        install_packages dante-server curl net-tools
    else
        install_packages dante-server curl net-tools # dante-server might just be dante in EPEL
    fi
    
    # Handle danted vs dante-server service names
    local service_name="danted"
    if systemctl list-unit-files | grep -q "^dante-server"; then
        service_name="dante-server"
    fi
    
    # Configure
    generate_dante_conf "$auth"
    
    # Firewall
    configure_firewall 1080
    
    # Service
    print_info "Restarting and enabling Dante ($service_name)..."
    systemctl enable "$service_name" >/dev/null 2>&1
    systemctl restart "$service_name" >/dev/null 2>&1
    
    check_result $? "Dante started successfully" "Failed to start Dante" true
    
    if [[ "$auth" == "true" ]]; then
        print_info "To add users for Dante, they must be system users."
        print_info "Example: useradd -M -s /sbin/nologin user && passwd user"
    fi
    
    print_success "Dante installation completed!"
}

# Allow script to be run directly or sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    auth_req="true"
    if [[ "$1" == "--no-auth" ]]; then
        auth_req="false"
    fi
    install_dante "$auth_req"
fi
