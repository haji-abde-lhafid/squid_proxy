#!/usr/bin/env bash

# ==============================================================================
# Clear Proxy Cache & Logs
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true

clear_cache() {
    show_header
    print_info "Starting Proxy Cache & Log Cleanup..."
    
    check_root
    
    local has_squid=false
    local has_dante=false
    
    if systemctl list-unit-files | grep -q "^squid"; then
        has_squid=true
    fi
    if systemctl list-unit-files | grep -Eq "^(dante-server|danted|sockd|dante)"; then
        has_dante=true
    fi
    
    if [[ "$has_squid" == "true" ]]; then
        print_info "Stopping Squid service..."
        systemctl stop squid >/dev/null 2>&1 || true
        
        print_info "Clearing Squid spool cache..."
        rm -rf /var/spool/squid/* 2>/dev/null || true
        
        print_info "Clearing Squid logs..."
        if [[ -d /var/log/squid ]]; then
            > /var/log/squid/access.log 2>/dev/null || true
            > /var/log/squid/cache.log 2>/dev/null || true
        fi
        
        print_info "Re-initializing Squid cache structure..."
        squid -z >/dev/null 2>&1 || true
        
        print_info "Restarting Squid..."
        systemctl start squid >/dev/null 2>&1
        check_result $? "Squid cache cleared and restarted successfully" "Failed to restart Squid" true
    fi
    
    if [[ "$has_dante" == "true" ]]; then
        local service_name=$(systemctl list-unit-files | grep -Eo "^(dante-server|danted|sockd|dante)" | head -n1)
        print_info "Clearing Dante logs..."
        > /var/log/danted.log 2>/dev/null || true
        chmod 666 /var/log/danted.log 2>/dev/null || true
        
        print_info "Restarting Dante ($service_name)..."
        systemctl restart "$service_name" >/dev/null 2>&1
        check_result $? "Dante logs cleared and service restarted" "Failed to restart Dante" true
    fi
    
    if [[ "$has_squid" == "false" && "$has_dante" == "false" ]]; then
        print_warning "No installed proxy services detected."
    else
        print_success "Cache and log cleanup completed!"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    clear_cache
fi
