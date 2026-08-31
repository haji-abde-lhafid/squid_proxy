#!/usr/bin/env bash

# ==============================================================================
# Uninstall MicroSocks Proxy
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true

uninstall_microsocks() {
    show_header
    print_info "Starting MicroSocks Uninstallation..."
    
    check_root
    detect_system
    
    print_info "Stopping and disabling MicroSocks service..."
    systemctl stop microsocks >/dev/null 2>&1 || true
    systemctl disable microsocks >/dev/null 2>&1 || true
    pkill -9 -f microsocks 2>/dev/null || true
    
    print_info "Removing MicroSocks binary & systemd service..."
    rm -f /usr/local/bin/microsocks /usr/bin/microsocks
    rm -f /etc/systemd/system/microsocks.service
    systemctl daemon-reload
    
    # Close port 1080
    if command -v ufw &>/dev/null && ufw status | grep -qi "active"; then
        ufw delete allow 1080/tcp >/dev/null 2>&1
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --remove-port=1080/tcp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
    
    print_success "MicroSocks has been completely uninstalled."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    uninstall_microsocks
fi
