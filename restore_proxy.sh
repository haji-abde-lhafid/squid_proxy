#!/usr/bin/env bash

# ==============================================================================
# Restore Proxy Configurations
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

restore_proxy() {
    print_info "Starting Restore Process..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        print_error "Backup directory not found."
        return 1
    fi
    
    local backups=($(ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        print_error "No backups found in $BACKUP_DIR."
        return 1
    fi
    
    echo -e "${CYAN}Available Backups:${NC}"
    for i in "${!backups[@]}"; do
        echo "$((i+1))) $(basename "${backups[$i]}")"
    done
    
    local choice
    read -r -p "Select backup to restore (1-${#backups[@]}) or 0 to cancel: " choice
    
    if [[ "$choice" -eq 0 ]]; then
        print_info "Restore cancelled."
        return 0
    fi
    
    if [[ "$choice" -gt 0 && "$choice" -le "${#backups[@]}" ]]; then
        local selected="${backups[$((choice-1))]}"
        print_info "Restoring $selected..."
        
        # Extract to /
        if tar -xzf "$selected" -C / 2>/dev/null; then
            print_success "Backup restored successfully."
            log_msg "RESTORE" "Restored $selected"
            
            # Restart services if they exist
            if systemctl list-unit-files | grep -q "^squid"; then
                systemctl restart squid >/dev/null 2>&1
            fi
            if systemctl list-unit-files | grep -Eq "^(dante-server|danted)"; then
                local sname="danted"
                if systemctl list-unit-files | grep -q "^dante-server"; then
                    sname="dante-server"
                fi
                systemctl restart "$sname" >/dev/null 2>&1
            fi
        else
            print_error "Failed to extract backup."
            return 1
        fi
    else
        print_error "Invalid selection."
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    restore_proxy
fi
