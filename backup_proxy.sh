#!/usr/bin/env bash

# ==============================================================================
# Backup Proxy Configurations
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

backup_proxy() {
    print_info "Starting Backup Process..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
    fi
    
    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$BACKUP_DIR/proxy_backup_$ts.tar.gz"
    
    local targets=()
    
    if [[ -d "/etc/squid" ]]; then
        targets+=("/etc/squid")
    fi
    if [[ -f "/etc/sockd.conf" ]]; then
        targets+=("/etc/sockd.conf")
    fi
    
    if [[ ${#targets[@]} -eq 0 ]]; then
        print_error "No proxy configurations found to backup."
        return 1
    fi
    
    if tar -czf "$backup_file" "${targets[@]}" 2>/dev/null; then
        print_success "Backup created successfully at: $backup_file"
        log_msg "BACKUP" "Created $backup_file"
    else
        print_error "Failed to create backup."
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    backup_proxy
fi
