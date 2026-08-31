#!/usr/bin/env bash

# ==============================================================================
# Install MicroSocks (Lightweight, High-Performance SOCKS5 Proxy)
# Port: 1080 | Auth: rooot / aaaa5555
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true

SOCKS_PORT="1080"
DEFAULT_USER="rooot"
DEFAULT_PASS="aaaa5555"

install_microsocks() {
    local auth="${1:-true}"
    show_header
    print_info "Starting MicroSocks (SOCKS5) Installation..."
    
    check_root
    detect_system

    print_info "Installing build dependencies..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -qq
        apt-get install -y -q gcc make git curl net-tools
    else
        $PKG_MANAGER install -y gcc make git curl net-tools || true
    fi

    print_info "Downloading and building MicroSocks from source..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    git clone --depth 1 https://github.com/rofl0r/microsocks.git "$tmp_dir/microsocks" >/dev/null 2>&1 || {
        curl -sSL https://github.com/rofl0r/microsocks/archive/refs/heads/master.tar.gz | tar -xz -C "$tmp_dir"
        mv "$tmp_dir"/microsocks-* "$tmp_dir/microsocks" 2>/dev/null || true
    }

    cd "$tmp_dir/microsocks"
    make clean >/dev/null 2>&1 || true
    make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null 2>&1
    make install >/dev/null 2>&1 || cp microsocks /usr/local/bin/microsocks
    chmod +x /usr/local/bin/microsocks

    rm -rf "$tmp_dir"
    cd - >/dev/null

    print_info "Creating MicroSocks systemd service (/etc/systemd/system/microsocks.service)..."
    local exec_cmd="/usr/local/bin/microsocks -i 0.0.0.0 -p ${SOCKS_PORT}"
    
    if [[ "$auth" == "true" ]]; then
        exec_cmd="/usr/local/bin/microsocks -i 0.0.0.0 -p ${SOCKS_PORT} -u ${DEFAULT_USER} -P ${DEFAULT_PASS}"
    fi

    cat > /etc/systemd/system/microsocks.service << EOF
[Unit]
Description=MicroSocks SOCKS5 Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=${exec_cmd}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable microsocks >/dev/null 2>&1 || true
    systemctl restart microsocks >/dev/null 2>&1 || true

    # Firewall
    configure_firewall "$SOCKS_PORT"

    if systemctl is-active microsocks &>/dev/null; then
        print_success "MicroSocks SOCKS5 Proxy installed and started successfully!"
        print_info "Port     : ${SOCKS_PORT}"
        if [[ "$auth" == "true" ]]; then
            print_info "Username : ${DEFAULT_USER}"
            print_info "Password : ${DEFAULT_PASS}"
        fi
    else
        print_error "Failed to start MicroSocks service."
        journalctl -u microsocks --no-pager -n 20 2>/dev/null || true
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    auth_req="true"
    if [[ "$1" == "--no-auth" ]]; then
        auth_req="false"
    fi
    install_microsocks "$auth_req"
fi
