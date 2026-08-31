#!/usr/bin/env bash

# ==============================================================================
# Optimize Proxy Performance & Sysctl
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true
source "$(dirname "$0")/network_utils.sh" 2>/dev/null || true
source "$(dirname "$0")/install_squid.sh" 2>/dev/null || true
source "$(dirname "$0")/install_dante.sh" 2>/dev/null || true

optimize_proxy() {
    show_header
    print_info "Starting Proxy Optimization Process..."
    
    check_root
    detect_system
    detect_network
    
    print_info "Applying kernel network optimizations..."
    optimize_sysctl
    optimize_ulimit
    
    local has_squid=false
    local has_dante=false
    
    if systemctl list-unit-files | grep -q "^squid"; then
        has_squid=true
    fi
    
    if systemctl list-unit-files | grep -Eq "^(dante-server|danted)"; then
        has_dante=true
    fi
    
    if [[ "$has_squid" == "true" ]]; then
        print_info "Regenerating optimized Squid configuration..."
        # Check if auth file exists to retain auth setting
        local auth_req="false"
        if [[ -f "$PASSWD_FILE" && -s "$PASSWD_FILE" ]]; then
            auth_req="true"
        fi
        generate_squid_conf "$auth_req"
        
        print_info "Restarting Squid service..."
        systemctl restart squid >/dev/null 2>&1
        check_result $? "Squid optimized and restarted successfully" "Failed to restart Squid" true
    fi
    
    if [[ "$has_dante" == "true" ]]; then
        print_info "Regenerating optimized Dante configuration..."
        local service_name="danted"
        if systemctl list-unit-files | grep -q "^dante-server"; then
            service_name="dante-server"
        fi
        
        local auth_req="true"
        if grep -q "socksmethod: none" "$DANTE_CONF" 2>/dev/null; then
            auth_req="false"
        fi
        generate_dante_conf "$auth_req"
        
        # Symlink config for compatibility across Linux distros
        ln -sf /etc/sockd.conf /etc/danted.conf 2>/dev/null || true
        
        # Setup PAM Configuration for username authentication
        if [[ ! -f /etc/pam.d/sockd ]]; then
            cat > /etc/pam.d/sockd << 'EOF'
auth    required    pam_unix.so
account required    pam_unix.so
EOF
        fi
        if [[ ! -f /etc/pam.d/danted ]]; then
            cat > /etc/pam.d/danted << 'EOF'
auth    required    pam_unix.so
account required    pam_unix.so
EOF
        fi
        
        # Ensure log permissions
        touch /var/log/danted.log
        chmod 666 /var/log/danted.log
        
        print_info "Restarting Dante service..."
        systemctl restart "$service_name" >/dev/null 2>&1
        check_result $? "Dante optimized and restarted successfully" "Failed to restart Dante" true
    fi
    
    if [[ "$has_squid" == "false" && "$has_dante" == "false" ]]; then
        print_warning "No installed Squid or Dante proxy services detected."
    else
        print_success "Proxy optimization completed successfully!"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    optimize_proxy
fi
