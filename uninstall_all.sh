#!/usr/bin/env bash

# ==============================================================================
# Complete Server Proxy Purge Script (Clean All Proxy Installations)
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true

uninstall_all_proxies() {
    show_header
    print_info "Starting Complete Server Proxy Purge..."
    
    check_root
    detect_system

    print_info "Stopping all proxy services..."
    systemctl stop squid microsocks danted dante-server sockd dante 3proxy >/dev/null 2>&1 || true
    systemctl disable squid microsocks danted dante-server sockd dante 3proxy >/dev/null 2>&1 || true

    print_info "Killing lingering processes on ports 8888, 1080, 3128..."
    pkill -9 -f "squid|microsocks|sockd|danted|3proxy" 2>/dev/null || true
    if command -v fuser &>/dev/null; then
        fuser -k 8888/tcp 1080/tcp 3128/tcp >/dev/null 2>&1 || true
    fi

    print_info "Removing installed proxy packages..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get purge -y -q squid squid-common dante-server dante-client >/dev/null 2>&1 || true
        apt-get autoremove -y -q >/dev/null 2>&1 || true
    else
        $PKG_MANAGER remove -y squid dante-server dante >/dev/null 2>&1 || true
    fi

    print_info "Removing proxy binaries, configurations, logs, and caches..."
    rm -rf /etc/squid /var/log/squid /var/spool/squid
    rm -f /usr/local/bin/microsocks /usr/bin/microsocks
    rm -f /etc/systemd/system/microsocks.service
    rm -f /etc/sockd.conf /etc/danted.conf /etc/pam.d/sockd /etc/pam.d/danted /var/log/danted.log /var/run/danted
    rm -f /etc/sysctl.d/99-proxy-performance.conf
    
    systemctl daemon-reload

    print_info "Closing firewall ports (8888, 1080, 3128)..."
    close_firewall "8888"
    close_firewall "1080"
    close_firewall "3128"

    echo ""
    echo -e "${GREEN}${BOLD}==================================================${NC}"
    echo -e "${GREEN}${BOLD}🎉 Server Clean Completed! All proxies removed.  ${NC}"
    echo -e "${GREEN}${BOLD}==================================================${NC}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    uninstall_all_proxies
fi
