#!/usr/bin/env bash

# ==============================================================================
# All-In-One Optimized Proxy Master (Squid HTTP: 8888 & Dante SOCKS5: 1080)
# Works on: Ubuntu, Debian, CentOS, RHEL, Fedora, AlmaLinux, Amazon Linux
# Usage: sudo bash proxy_master.sh [--install | --uninstall | --clear-cache]
# ==============================================================================

set -e

# Terminal Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Default Configuration
HTTP_PORT="8888"
SOCKS_PORT="1080"
DEFAULT_USER="rooot"
DEFAULT_PASS="aaaa5555"

SQUID_CONF="/etc/squid/squid.conf"
PASSWD_FILE="/etc/squid/passwords"
DANTE_CONF="/etc/sockd.conf"

show_header() {
    clear
    echo -e "${CYAN}${BOLD}==================================================${NC}"
    echo -e "${CYAN}${BOLD}    Optimized HTTP (8888) & SOCKS5 (1080) Proxy   ${NC}"
    echo -e "${CYAN}${BOLD}==================================================${NC}"
    echo ""
}

print_info() { echo -e "${YELLOW}[i] $1${NC}"; }
print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_error() { echo -e "${RED}[✗] $1${NC}"; }
print_warning() { echo -e "${RED}${BOLD}[!] $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root: sudo bash $0"
        exit 1
    fi
}

detect_system() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi

    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    else
        print_error "Unsupported package manager."
        exit 1
    fi
}

detect_network() {
    DEFAULT_INTERFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1)
    if [[ -z "$DEFAULT_INTERFACE" ]]; then
        DEFAULT_INTERFACE=$(ip link show | awk -F: '$0 !~ "lo|vir|dock" {print $2}' | tr -d ' ' | head -n1)
    fi
    if [[ -z "$DEFAULT_INTERFACE" ]]; then
        DEFAULT_INTERFACE="eth0"
    fi
    
    ALL_IPV4=()
    while IFS= read -r ip; do
        [[ -n "$ip" ]] && ALL_IPV4+=("$ip")
    done < <(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '^127\.')
    
    PRIMARY_IPV4="${ALL_IPV4[0]:-127.0.0.1}"
    
    HAS_IPV6=false
    if ip -6 addr show 2>/dev/null | grep -q "inet6"; then
        HAS_IPV6=true
    fi
}

detect_dante_svc() {
    if systemctl list-unit-files 2>/dev/null | grep -q "^dante-server"; then
        echo "dante-server"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^danted"; then
        echo "danted"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^sockd"; then
        echo "sockd"
    elif systemctl list-unit-files 2>/dev/null | grep -q "^dante"; then
        echo "dante"
    else
        echo "danted"
    fi
}

optimize_kernel() {
    print_info "Applying high-concurrency kernel sysctl optimizations..."
    cat > /etc/sysctl.d/99-proxy-performance.conf << 'EOF'
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
    sysctl --system >/dev/null 2>&1 || true

    cat > /etc/security/limits.d/99-proxy-limits.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
    ulimit -n 65535 2>/dev/null || true
}

configure_firewall() {
    local port="$1"
    if command -v ufw &>/dev/null && ufw status | grep -qi "active"; then
        ufw allow "${port}/tcp" >/dev/null 2>&1
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v iptables &>/dev/null; then
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    fi
}

close_firewall() {
    local port="$1"
    if command -v ufw &>/dev/null && ufw status | grep -qi "active"; then
        ufw delete allow "${port}/tcp" >/dev/null 2>&1
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --remove-port="${port}/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
}

ensure_htpasswd() {
    if ! command -v htpasswd &>/dev/null; then
        if [[ "$PKG_MANAGER" == "apt" ]]; then
            apt-get update -qq && apt-get install -y -q apache2-utils >/dev/null 2>&1
        else
            $PKG_MANAGER install -y httpd-tools >/dev/null 2>&1 || true
        fi
    fi
}

add_user_cmd() {
    local username="${1:-$DEFAULT_USER}"
    local password="${2:-$DEFAULT_PASS}"
    
    mkdir -p /etc/squid
    touch "$PASSWD_FILE"
    chmod 644 "$PASSWD_FILE"

    # Add to Squid htpasswd
    ensure_htpasswd
    htpasswd -b "$PASSWD_FILE" "$username" "$password" >/dev/null 2>&1 || \
    printf "$username:$(openssl passwd -crypt $password)\n" >> "$PASSWD_FILE"

    # Add to Dante system user
    if ! id "$username" &>/dev/null; then
        useradd -M -s /usr/sbin/nologin "$username" >/dev/null 2>&1 || \
        useradd -M -s /sbin/nologin "$username" >/dev/null 2>&1 || true
    fi
    echo "$username:$password" | chpasswd >/dev/null 2>&1 || true
    
    print_success "User $username configured for Squid & Dante."
}

delete_user_cmd() {
    local username="$1"
    if [[ -z "$username" ]]; then
        read -r -p "Enter username to delete: " username
    fi
    [[ -z "$username" ]] && return
    
    if [[ -f "$PASSWD_FILE" ]]; then
        ensure_htpasswd
        htpasswd -D "$PASSWD_FILE" "$username" >/dev/null 2>&1 || true
    fi
    if id "$username" &>/dev/null; then
        userdel -f "$username" >/dev/null 2>&1 || true
    fi
    systemctl reload squid >/dev/null 2>&1 || true
    print_success "User $username deleted."
}

list_users_cmd() {
    echo -e "${CYAN}--- Active Squid Users ---${NC}"
    if [[ -s "$PASSWD_FILE" ]]; then
        awk -F':' '{print "- " $1}' "$PASSWD_FILE"
    else
        echo "No Squid users."
    fi
    
    echo -e "\n${CYAN}--- Active Dante Users ---${NC}"
    local d_users
    d_users=$(awk -F':' '($3 >= 1000) && ($7 ~ /nologin|false/) {print $1}' /etc/passwd)
    if [[ -n "$d_users" ]]; then
        for u in $d_users; do echo "- $u"; done
    else
        echo "No Dante users."
    fi
}

install_squid_conf() {
    print_info "Building optimized Squid (HTTP) configuration on port $HTTP_PORT..."
    mkdir -p /etc/squid /var/log/squid /var/spool/squid
    
    local auth_param="/usr/lib/squid/basic_ncsa_auth"
    if [[ -f "/usr/lib64/squid/basic_ncsa_auth" ]]; then
        auth_param="/usr/lib64/squid/basic_ncsa_auth"
    else
        local found_path
        found_path=$(find /usr -name "basic_ncsa_auth" 2>/dev/null | head -n1)
        [[ -n "$found_path" ]] && auth_param="$found_path"
    fi

    cat > "$SQUID_CONF" << EOF
# ============================================================
# High-Performance Squid Proxy Configuration
# ============================================================

visible_hostname $(hostname -f 2>/dev/null || echo "proxy-master")
dns_v4_first on
dns_nameservers 1.1.1.1 8.8.8.8
ipcache_size 10240
ipcache_low 90
ipcache_high 95
fqdncache_size 10240

auth_param basic program ${auth_param} ${PASSWD_FILE}
auth_param basic children 64 startup=10 idle=5
auth_param basic realm Proxy Authentication
auth_param basic credentialsttl 2 hours
acl authenticated proxy_auth REQUIRED

# Ports & ACLs
http_port 0.0.0.0:${HTTP_PORT}
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl CONNECT method CONNECT

http_access allow CONNECT authenticated SSL_ports
http_access allow authenticated
http_access allow localhost
http_access deny all

# Header Preservation & Anonymity
forwarded_for delete
via off
request_header_access Allow allow all
request_header_access Authorization allow all
request_header_access Proxy-Authorization allow all
request_header_access Cache-Control allow all
request_header_access Content-Type allow all
request_header_access Host allow all
request_header_access Connection allow all
request_header_access Keep-Alive allow all
request_header_access User-Agent allow all

# Buffering & Logging
access_log daemon:/var/log/squid/access.log buffer-size=64KB squid
cache_log /var/log/squid/cache.log
maximum_object_size 256 MB
cache_dir ufs /var/spool/squid 1000 16 256
EOF
    chown -R proxy:proxy /var/log/squid /var/spool/squid /etc/squid 2>/dev/null || chown -R squid:squid /var/log/squid /var/spool/squid /etc/squid 2>/dev/null || true
    chmod -R 755 /var/log/squid /var/spool/squid 2>/dev/null || true
    squid -z >/dev/null 2>&1 || true
}

install_dante_conf() {
    print_info "Building optimized Dante (SOCKS5) configuration on port $SOCKS_PORT..."
    
    cat > "$DANTE_CONF" << EOF
# ============================================================
# High-Performance Dante SOCKS5 Configuration
# ============================================================

logoutput: /var/log/danted.log
user.privileged: root
user.notprivileged: nobody
timeout.connect: 30
timeout.io: 60
timeout.negotiate: 30
srch_domain: off
clientmethod: none

# Internal Interface Bindings
internal: 127.0.0.1 port = ${SOCKS_PORT}
EOF

    if [[ -n "$DEFAULT_INTERFACE" ]]; then
        echo "internal: ${DEFAULT_INTERFACE} port = ${SOCKS_PORT}" >> "$DANTE_CONF"
    fi
    for ip in "${ALL_IPV4[@]}"; do
        if [[ "$ip" != "127.0.0.1" ]]; then
            echo "internal: ${ip} port = ${SOCKS_PORT}" >> "$DANTE_CONF"
        fi
    done
    if [[ "$HAS_IPV6" == "true" ]]; then
        echo "internal: ::0 port = ${SOCKS_PORT}" >> "$DANTE_CONF"
    fi

    cat >> "$DANTE_CONF" << EOF

# External Interface
external: ${DEFAULT_INTERFACE}
socksmethod: username

# Client Rules
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

# Socks Authentication Rules
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF

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
}

install_all() {
    show_header
    check_root
    detect_system
    detect_network
    optimize_kernel

    print_info "Installing Squid & Dante packages..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get update -qq
        apt-get install -y -q squid dante-server apache2-utils curl net-tools
    else
        $PKG_MANAGER install -y squid dante-server httpd-tools curl net-tools || \
        $PKG_MANAGER install -y squid dante httpd-tools curl net-tools
    fi

    install_squid_conf
    install_dante_conf
    add_user_cmd "$DEFAULT_USER" "$DEFAULT_PASS"

    configure_firewall "$HTTP_PORT"
    configure_firewall "$SOCKS_PORT"

    print_info "Starting Squid & Dante services..."
    systemctl enable squid >/dev/null 2>&1 || true
    systemctl restart squid >/dev/null 2>&1 || true

    local dante_svc
    dante_svc=$(detect_dante_svc)
    systemctl enable "$dante_svc" >/dev/null 2>&1 || true
    systemctl restart "$dante_svc" >/dev/null 2>&1 || true

    echo ""
    echo -e "${GREEN}${BOLD}==================================================${NC}"
    echo -e "${GREEN}${BOLD}🎉 Installation Completed Successfully!           ${NC}"
    echo -e "${GREEN}${BOLD}==================================================${NC}"
    echo -e "Server IP    : ${PRIMARY_IPV4}"
    echo -e "HTTP Proxy   : http://${DEFAULT_USER}:${DEFAULT_PASS}@${PRIMARY_IPV4}:${HTTP_PORT}"
    echo -e "SOCKS5 Proxy : socks5h://${DEFAULT_USER}:${DEFAULT_PASS}@${PRIMARY_IPV4}:${SOCKS_PORT}"
    echo -e "Username     : ${DEFAULT_USER}"
    echo -e "Password     : ${DEFAULT_PASS}"
    echo -e "${GREEN}${BOLD}==================================================${NC}"
}

uninstall_all() {
    show_header
    check_root
    detect_system

    print_info "Stopping proxy services..."
    systemctl stop squid >/dev/null 2>&1 || true
    systemctl disable squid >/dev/null 2>&1 || true
    systemctl stop danted dante-server sockd >/dev/null 2>&1 || true
    systemctl disable danted dante-server sockd >/dev/null 2>&1 || true
    pkill -9 -f "squid|sockd|danted" 2>/dev/null || true

    print_info "Removing packages & configurations..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        apt-get purge -y -q squid squid-common dante-server dante-client >/dev/null 2>&1 || true
        apt-get autoremove -y -q >/dev/null 2>&1 || true
    else
        $PKG_MANAGER remove -y squid dante-server dante >/dev/null 2>&1 || true
    fi

    rm -rf /etc/squid /var/log/squid /var/spool/squid
    rm -f /etc/sockd.conf /etc/danted.conf /etc/pam.d/sockd /etc/pam.d/danted /var/log/danted.log

    close_firewall "$HTTP_PORT"
    close_firewall "$SOCKS_PORT"
    close_firewall "3128"

    print_success "Proxy services completely uninstalled!"
}

clear_cache() {
    show_header
    check_root

    print_info "Cleaning Squid spool cache..."
    systemctl stop squid >/dev/null 2>&1 || true
    rm -rf /var/spool/squid/* 2>/dev/null || true
    > /var/log/squid/access.log 2>/dev/null || true
    > /var/log/squid/cache.log 2>/dev/null || true
    squid -z >/dev/null 2>&1 || true
    systemctl start squid >/dev/null 2>&1 || true

    print_info "Cleaning Dante logs..."
    > /var/log/danted.log 2>/dev/null || true
    chmod 666 /var/log/danted.log 2>/dev/null || true
    
    local dante_svc="danted"
    if systemctl list-unit-files | grep -q "^dante-server"; then
        dante_svc="dante-server"
    elif systemctl list-unit-files | grep -q "^sockd"; then
        dante_svc="sockd"
    fi
    systemctl restart "$dante_svc" >/dev/null 2>&1 || true

    print_success "Cache and log files cleared successfully!"
}

monitor_status() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}==========================================${NC}"
        echo -e "${CYAN}${BOLD}         Live Proxy Monitor               ${NC}"
        echo -e "${CYAN}${BOLD}==========================================${NC}"
        echo -e "Press [Ctrl+C] to exit..."
        echo ""

        local cpu_usage
        cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        local mem_info
        mem_info=$(free -m)
        local mem_used
        mem_used=$(echo "$mem_info" | awk '/^Mem:/{print $3}')
        local mem_total
        mem_total=$(echo "$mem_info" | awk '/^Mem:/{print $2}')
        local mem_perc
        mem_perc=$(awk "BEGIN {printf \"%.2f\", ($mem_used/$mem_total)*100}")

        echo -e "${BOLD}--- System ---${NC}"
        echo -e "CPU Usage : ${cpu_usage}%"
        echo -e "RAM Usage : ${mem_used}MB / ${mem_total}MB (${mem_perc}%)"
        echo ""

        echo -e "${BOLD}--- Network ---${NC}"
        local total_conn
        total_conn=$(ss -s 2>/dev/null | awk '/TCP:/{print $2}')
        echo -e "Total TCP Connections: ${total_conn:-0}"

        echo -e "\n${BOLD}--- Squid Proxy (Port $HTTP_PORT) ---${NC}"
        if systemctl is-active squid &>/dev/null; then
            local squid_conn
            squid_conn=$(ss -tn state established '( sport = :'${HTTP_PORT}' )' 2>/dev/null | wc -l)
            squid_conn=$((squid_conn - 1))
            [[ $squid_conn -lt 0 ]] && squid_conn=0
            echo -e "Active Connections: $squid_conn"
            echo -e "Status: ${GREEN}Running${NC}"
        else
            echo -e "Status: ${RED}Stopped${NC}"
        fi

        echo -e "\n${BOLD}--- Dante Proxy (Port $SOCKS_PORT) ---${NC}"
        local dante_svc=""
        if systemctl list-unit-files | grep -Eq "^(dante-server|danted|sockd|dante)"; then
            dante_svc=$(systemctl list-unit-files | grep -Eo "^(dante-server|danted|sockd|dante)" | head -n1)
        fi

        if [[ -n "$dante_svc" ]]; then
            if systemctl is-active "$dante_svc" &>/dev/null; then
                local dante_conn
                dante_conn=$(ss -tn state established '( sport = :'${SOCKS_PORT}' )' 2>/dev/null | wc -l)
                dante_conn=$((dante_conn - 1))
                [[ $dante_conn -lt 0 ]] && dante_conn=0
                echo -e "Active Connections: $dante_conn"
                echo -e "Status: ${GREEN}Running${NC}"
            else
                echo -e "Status: ${RED}Stopped${NC}"
            fi
        else
            echo -e "Status: ${YELLOW}Not Installed${NC}"
        fi

        sleep 1
    done
}

manage_users_menu() {
    while true; do
        show_header
        echo -e "${CYAN}${BOLD}--- User Management ---${NC}"
        echo -e "${YELLOW}1)${NC} Add User"
        echo -e "${YELLOW}2)${NC} Delete User"
        echo -e "${YELLOW}3)${NC} List Users"
        echo -e "${BOLD}0)${NC} Back to Main Menu"
        echo ""
        read -r -p "Enter choice [0-3]: " uchoice
        case $uchoice in
            1) 
                read -r -p "Enter username: " u
                read -r -s -p "Enter password: " p
                echo ""
                add_user_cmd "$u" "$p"
                read -r -p "Press Enter to continue..."
                ;;
            2) delete_user_cmd; read -r -p "Press Enter to continue..." ;;
            3) list_users_cmd; read -r -p "Press Enter to continue..." ;;
            0) break ;;
            *) print_error "Invalid choice."; sleep 1 ;;
        esac
    done
}

main_menu() {
    while true; do
        show_header
        echo -e "${GREEN}${BOLD}1)${NC} Install Proxy (HTTP: 8888 | SOCKS5: 1080)"
        echo -e "${RED}${BOLD}2)${NC} Uninstall Proxy (Complete Wipe)"
        echo -e "${BLUE}${BOLD}3)${NC} Monitor Proxy Status"
        echo -e "${YELLOW}${BOLD}4)${NC} Clear Cache & Clean Logs"
        echo -e "${CYAN}${BOLD}5)${NC} Manage Users"
        echo -e "${BOLD}0)${NC} Exit"
        echo ""
        read -r -p "Enter your choice [0-5]: " choice
        case $choice in
            1) install_all; read -r -p "Press Enter to continue..." ;;
            2) uninstall_all; read -r -p "Press Enter to continue..." ;;
            3) monitor_status ;;
            4) clear_cache; read -r -p "Press Enter to continue..." ;;
            5) manage_users_menu ;;
            0) print_info "Exiting..."; exit 0 ;;
            *) print_error "Invalid choice."; sleep 1 ;;
        esac
    done
}

# CLI Flags
if [[ "$1" == "--install" ]]; then
    install_all
    exit 0
elif [[ "$1" == "--uninstall" ]]; then
    uninstall_all
    exit 0
elif [[ "$1" == "--clear-cache" ]]; then
    clear_cache
    exit 0
fi

# Default execution: Main Menu
check_root
main_menu
