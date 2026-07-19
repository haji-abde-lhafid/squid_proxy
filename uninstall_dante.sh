#!/usr/bin/env bash

# ==============================================================================
# Uninstall Dante Proxy
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true

uninstall_dante() {
    show_header
    print_info "Starting Dante Uninstallation..."
    
    check_root
    detect_system
    
    if prompt_confirm "Are you sure you want to completely uninstall Dante Proxy?" "N"; then
        print_info "Stopping and disabling Dante service..."
        local service_name="danted"
        if systemctl list-unit-files | grep -q "^dante-server"; then
            service_name="dante-server"
        fi
        systemctl stop "$service_name" >/dev/null 2>&1
        systemctl disable "$service_name" >/dev/null 2>&1
        
        print_info "Removing packages..."
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            execute_cmd "Purging dante-server" apt-get purge -y -q dante-server dante-client
            execute_cmd "Removing unused dependencies" apt-get autoremove -y -q
        else
            execute_cmd "Removing dante" $PKG_MANAGER remove -y dante-server dante
        fi
        
        print_info "Removing configuration and data..."
        rm -f /etc/sockd.conf
        rm -f /var/log/danted.log
        rm -rf /var/run/danted
        
        # Open port closing
        if command -v ufw &>/dev/null && ufw status | grep -qi "active"; then
            ufw delete allow 1080/tcp >/dev/null 2>&1
            ufw delete allow 1080/udp >/dev/null 2>&1
        elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
            firewall-cmd --remove-port=1080/tcp --permanent >/dev/null 2>&1
            firewall-cmd --remove-port=1080/udp --permanent >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        
        print_success "Dante has been completely uninstalled."
    else
        print_info "Uninstallation aborted."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    uninstall_dante
fi
