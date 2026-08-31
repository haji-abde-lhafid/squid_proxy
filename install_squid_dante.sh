#!/usr/bin/env bash

# ==============================================================================
# Install Squid + Dante Proxies
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

install_both() {
    local auth="${1:-true}"
    
    show_header
    print_info "Starting Squid + MicroSocks Installation..."
    
    bash "$(dirname "$0")/install_squid.sh" "$auth"
    local sq_status=$?
    
    local da_status=0
    if [[ -f "$(dirname "$0")/install_microsocks.sh" ]]; then
        bash "$(dirname "$0")/install_microsocks.sh" "$auth"
        da_status=$?
    elif [[ -f "$(dirname "$0")/proxy_master.sh" ]]; then
        bash "$(dirname "$0")/proxy_master.sh" --install
        da_status=$?
    else
        print_info "Installing MicroSocks build dependencies..."
        if command -v apt-get &>/dev/null; then
            apt-get install -y -q gcc make git curl net-tools >/dev/null 2>&1
        else
            yum install -y gcc make git curl net-tools >/dev/null 2>&1 || dnf install -y gcc make git curl net-tools >/dev/null 2>&1 || true
        fi
        local tmp_dir=$(mktemp -d)
        git clone --depth 1 https://github.com/rofl0r/microsocks.git "$tmp_dir/microsocks" >/dev/null 2>&1 || true
        if [[ -d "$tmp_dir/microsocks" ]]; then
            cd "$tmp_dir/microsocks" && make >/dev/null 2>&1 && make install >/dev/null 2>&1 || cp microsocks /usr/local/bin/microsocks 2>/dev/null || true
            cd - >/dev/null
            cat > /etc/systemd/system/microsocks.service << EOF
[Unit]
Description=MicroSocks SOCKS5 Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/microsocks -i 0.0.0.0 -p 1080 -u rooot -P aaaa5555
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload && systemctl enable microsocks >/dev/null 2>&1 && systemctl restart microsocks >/dev/null 2>&1
            da_status=$?
        else
            da_status=1
        fi
        rm -rf "$tmp_dir"
    fi
    
    if [[ $sq_status -eq 0 && $da_status -eq 0 ]]; then
        print_success "Squid and MicroSocks installed successfully!"
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
