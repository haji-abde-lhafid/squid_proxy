#!/usr/bin/env bash

# ==============================================================================
# Network Utilities
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true

declare -g PRIMARY_IPV4=""
declare -g -a ALL_IPV4=()
declare -g DEFAULT_INTERFACE=""
declare -g HAS_IPV6=false

# Check if a string is a valid IPv4
is_valid_ipv4() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# Detect default interface
detect_default_interface() {
    DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [[ -z "$DEFAULT_INTERFACE" ]]; then
        print_error "Could not detect default network interface."
        exit 1
    fi
    print_info "Default Interface: $DEFAULT_INTERFACE"
}

# Detect primary public IP
detect_primary_ip() {
    PRIMARY_IPV4=$(curl -s4 --max-time 3 api.ipify.org)
    if [[ -z "$PRIMARY_IPV4" ]] || ! is_valid_ipv4 "$PRIMARY_IPV4"; then
        PRIMARY_IPV4=$(curl -s4 --max-time 3 ifconfig.me)
    fi
    
    if [[ -z "$PRIMARY_IPV4" ]] || ! is_valid_ipv4 "$PRIMARY_IPV4"; then
        # Fallback to local IP if curl fails
        PRIMARY_IPV4=$(ip -4 addr show "$DEFAULT_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    fi
    
    if [[ -n "$PRIMARY_IPV4" ]]; then
        print_info "Primary IPv4: $PRIMARY_IPV4"
    else
        print_error "Could not detect primary IPv4 address."
        exit 1
    fi
}

# Detect all IPv4 addresses
detect_all_ips() {
    local ips
    ips=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1')
    
    ALL_IPV4=()
    for ip in $ips; do
        ALL_IPV4+=("$ip")
    done
    
    print_info "Found ${#ALL_IPV4[@]} IPv4 addresses."
}

# Check IPv6 support
detect_ipv6() {
    if ip -6 addr | grep -q "inet6" && ! ip -6 addr | grep -q "inet6 ::1/128 scope host"; then
        HAS_IPV6=true
        print_info "IPv6 support detected."
    else
        HAS_IPV6=false
        print_info "No IPv6 support detected."
    fi
}

# Run all detection
detect_network() {
    print_info "Detecting network configuration..."
    detect_default_interface
    detect_primary_ip
    detect_all_ips
    detect_ipv6
}
