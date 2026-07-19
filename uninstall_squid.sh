#!/usr/bin/env bash

# ==============================================================================
# Uninstall Squid Proxy
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true

uninstall_squid() {
    show_header
    print_info "Starting Squid Uninstallation..."
    
    check_root
    detect_system
    
    if prompt_confirm "Are you sure you want to completely uninstall Squid Proxy?" "N"; then
        print_info "Stopping and disabling Squid service..."
        systemctl stop squid >/dev/null 2>&1
        systemctl disable squid >/dev/null 2>&1
        
        print_info "Removing packages..."
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            execute_cmd "Purging squid" apt-get purge -y -q squid squid-common
            execute_cmd "Removing unused dependencies" apt-get autoremove -y -q
        else
            execute_cmd "Removing squid" $PKG_MANAGER remove -y squid
        fi
        
        print_info "Removing configuration and data directories..."
        rm -rf /etc/squid
        rm -rf /var/log/squid
        rm -rf /var/spool/squid
        
        # Open port closing
        if command -v ufw &>/dev/null && ufw status | grep -qi "active"; then
            ufw delete allow 3128/tcp >/dev/null 2>&1
            ufw delete allow 3128/udp >/dev/null 2>&1
        elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
            firewall-cmd --remove-port=3128/tcp --permanent >/dev/null 2>&1
            firewall-cmd --remove-port=3128/udp --permanent >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
        fi
        
        print_success "Squid has been completely uninstalled."
    else
        print_info "Uninstallation aborted."
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    uninstall_squid
fi
