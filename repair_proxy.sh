#!/usr/bin/env bash

# ==============================================================================
# Repair Proxy Installation
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

repair_squid() {
    print_info "Checking Squid configuration..."
    if squid -k parse &>/dev/null; then
        print_success "Squid configuration is valid."
    else
        print_error "Squid configuration has errors!"
        squid -k parse
        if [[ -f "/etc/squid/squid.conf.orig" ]]; then
            if prompt_confirm "Restore original Squid config?" "y"; then
                cp "/etc/squid/squid.conf.orig" "/etc/squid/squid.conf"
                print_success "Restored original Squid configuration."
            fi
        fi
    fi
    
    print_info "Fixing Squid permissions..."
    mkdir -p /var/log/squid /var/spool/squid
    chown -R proxy:proxy /var/log/squid /var/spool/squid 2>/dev/null || chown -R squid:squid /var/log/squid /var/spool/squid 2>/dev/null
    chmod -R 755 /var/log/squid
    
    print_info "Restarting Squid..."
    if systemctl restart squid >/dev/null 2>&1; then
        print_success "Squid repaired and restarted."
    else
        print_error "Failed to restart Squid."
    fi
}

repair_dante() {
    local service_name="danted"
    if systemctl list-unit-files | grep -q "^dante-server"; then
        service_name="dante-server"
    fi
    
    print_info "Fixing Dante permissions..."
    touch /var/log/danted.log
    chmod 644 /var/log/danted.log
    
    print_info "Restarting Dante..."
    if systemctl restart "$service_name" >/dev/null 2>&1; then
        print_success "Dante repaired and restarted."
    else
        print_error "Failed to restart Dante."
    fi
}

repair_proxy() {
    print_info "Starting Repair Process..."
    
    local found=0
    
    if systemctl list-unit-files | grep -q "^squid"; then
        repair_squid
        found=1
    fi
    
    if systemctl list-unit-files | grep -Eq "^(dante-server|danted)"; then
        repair_dante
        found=1
    fi
    
    if [[ $found -eq 0 ]]; then
        print_warning "No installed proxy services detected."
    fi
    
    print_success "Repair process completed."
    log_msg "REPAIR" "Repair script executed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    repair_proxy
fi
