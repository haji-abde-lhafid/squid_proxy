#!/usr/bin/env bash

# ==============================================================================
# Install Squid + Dante Proxies
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

install_both() {
    local auth="${1:-true}"
    
    show_header
    print_info "Starting Squid + Dante Installation..."
    
    bash "$(dirname "$0")/install_squid.sh" "$auth"
    local sq_status=$?
    
    bash "$(dirname "$0")/install_dante.sh" "$auth"
    local da_status=$?
    
    if [[ $sq_status -eq 0 && $da_status -eq 0 ]]; then
        print_success "Squid and Dante installed successfully!"
    else
        print_error "One or more installations failed. Please check the logs."
    fi
}

# Allow script to be run directly or sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    auth_req="true"
    if [[ "$1" == "--no-auth" ]]; then
        auth_req="false"
    fi
    install_both "$auth_req"
fi
