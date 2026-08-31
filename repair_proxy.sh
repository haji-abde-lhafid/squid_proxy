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
    
    print_info "Fixing Dante permissions, PAM, and symlinks..."
    ln -sf /etc/sockd.conf /etc/danted.conf 2>/dev/null || true
    
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
    
    touch /var/log/danted.log
    chmod 666 /var/log/danted.log
    
    print_info "Restarting Dante..."
    if systemctl restart "$service_name" >/dev/null 2>&1; then
        print_success "Dante repaired and restarted."
    else
        print_error "Failed to restart Dante."
        journalctl -u "$service_name" --no-pager -n 20 2>/dev/null || true
    fi
}

repair_microsocks() {
    print_info "Repairing MicroSocks SOCKS5 Service..."
    
    print_info "Checking for port 1080 conflicts..."
    local active_proc
    active_proc=$(ss -tulpn 2>/dev/null | grep ":1080" || true)
    if [[ -n "$active_proc" ]]; then
        print_warning "Port 1080 is currently occupied by: $active_proc"
        print_info "Clearing port 1080 occupancy..."
        systemctl stop danted dante-server sockd dante 3proxy >/dev/null 2>&1 || true
        pkill -9 -f "sockd|danted|3proxy" 2>/dev/null || true
        if command -v fuser &>/dev/null; then
            fuser -k 1080/tcp >/dev/null 2>&1 || true
        fi
        sleep 1
    fi

    if [[ ! -f /etc/systemd/system/microsocks.service ]]; then
        print_info "Recreating MicroSocks systemd unit file..."
        cat > /etc/systemd/system/microsocks.service << 'EOF'
[Unit]
Description=MicroSocks SOCKS5 Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/microsocks -i 0.0.0.0 -p 1080 -u rooot -P aaaa5555
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
    fi

    print_info "Restarting MicroSocks..."
    systemctl daemon-reload
    systemctl enable microsocks >/dev/null 2>&1 || true
    if systemctl restart microsocks >/dev/null 2>&1; then
        print_success "MicroSocks repaired and restarted."
    else
        print_error "Failed to restart MicroSocks."
        journalctl -u microsocks --no-pager -n 20 2>/dev/null || true
    fi
}

repair_proxy() {
    print_info "Starting Repair Process..."
    
    local found=0
    
    if systemctl list-unit-files | grep -q "^squid"; then
        repair_squid
        found=1
    fi
    
    if systemctl list-unit-files | grep -q "^microsocks" || [[ -f /usr/local/bin/microsocks ]]; then
        repair_microsocks
        found=1
    elif systemctl list-unit-files | grep -Eq "^(dante-server|danted)"; then
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
