#!/usr/bin/env bash

# ==============================================================================
# System Utilities
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

# Global variables to store detected info
declare -g OS_ID=""
declare -g OS_VERSION=""
declare -g PKG_MANAGER=""
declare -g CPU_CORES=1
declare -g RAM_MB=0
declare -g SWAP_MB=0
declare -g ARCH=""

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root."
        exit 1
    fi
}

check_internet() {
    print_info "Checking internet connection..."
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        print_error "No internet connection detected."
        exit 1
    fi
    print_success "Internet connection verified."
}

detect_system() {
    print_info "Detecting system specifications..."
    
    # OS Detection
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "Unsupported OS."
        exit 1
    fi
    
    # Package Manager
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    else
        print_error "Supported package manager not found."
        exit 1
    fi
    
    # CPU
    CPU_CORES=$(nproc)
    
    # RAM and SWAP (in MB)
    RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    SWAP_MB=$(free -m | awk '/^Swap:/{print $2}')
    
    # Architecture
    ARCH=$(uname -m)
    
    print_success "System: $OS_ID $OS_VERSION ($ARCH), $CPU_CORES Cores, ${RAM_MB}MB RAM, ${SWAP_MB}MB Swap"
}

disable_selinux() {
    if command -v setenforce &>/dev/null; then
        if getenforce | grep -qi "Enforcing"; then
            print_info "Disabling SELinux..."
            setenforce 0 || true
            if [[ -f /etc/selinux/config ]]; then
                sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
            fi
            print_success "SELinux disabled."
        fi
    fi
}

configure_firewall() {
    local ports=("$@")
    print_info "Configuring firewall..."
    
    # UFW
    if command -v ufw &>/dev/null && ufw status | grep -qi "active"; then
        for port in "${ports[@]}"; do
            ufw allow "$port/tcp" >/dev/null 2>&1
            ufw allow "$port/udp" >/dev/null 2>&1
        done
        print_success "UFW configured."
    # Firewalld
    elif command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        for port in "${ports[@]}"; do
            firewall-cmd --add-port="$port/tcp" --permanent >/dev/null 2>&1
            firewall-cmd --add-port="$port/udp" --permanent >/dev/null 2>&1
        done
        firewall-cmd --reload >/dev/null 2>&1
        print_success "Firewalld configured."
    # Iptables
    elif command -v iptables &>/dev/null; then
        for port in "${ports[@]}"; do
            iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
            iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || iptables -A INPUT -p udp --dport "$port" -j ACCEPT
        done
        # Try to save
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save >/dev/null 2>&1
        elif command -v iptables-save &>/dev/null; then
            iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
        fi
        print_success "Iptables configured."
    else
        print_warning "No recognized active firewall detected."
    fi
}

install_packages() {
    local pkgs=("$@")
    print_info "Installing dependencies..."
    
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        execute_cmd "Updating package lists" apt-get update -y -q
        execute_cmd "Installing packages" apt-get install -y -q "${pkgs[@]}"
    elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
        execute_cmd "Installing EPEL repository" $PKG_MANAGER install -y epel-release
        execute_cmd "Installing packages" $PKG_MANAGER install -y "${pkgs[@]}"
    fi
    check_result $? "Dependencies installed successfully" "Failed to install dependencies"
}

optimize_sysctl() {
    print_info "Optimizing sysctl network settings..."
    local sysctl_file="/etc/sysctl.d/99-proxy-optimize.conf"
    
    cat > "$sysctl_file" << 'EOF'
fs.file-max = 1048576
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_syncookies = 1
EOF
    
    sysctl -p "$sysctl_file" >/dev/null 2>&1
    check_result $? "Sysctl optimized" "Failed to apply sysctl settings" true
}

optimize_ulimit() {
    print_info "Optimizing file limits..."
    local limits_file="/etc/security/limits.d/99-proxy.conf"
    
    cat > "$limits_file" << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF

    ulimit -n 1048576 2>/dev/null || true
    print_success "File limits optimized."
}
