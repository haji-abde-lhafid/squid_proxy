#!/bin/bash

# check_proxy_services.sh
# Checks if Squid and Dante (SOCKS5) are running. Re-starts them if they are down.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root: sudo bash $0"
    exit 1
fi

# Function to check and start a service
check_and_start_service() {
    local service_name=$1
    local display_name=$2

    # Check if service is active
    if systemctl is-active --quiet "$service_name"; then
        print_status "$display_name ($service_name) is running."
    else
        print_error "$display_name ($service_name) is NOT running."
        print_info "Attempting to start $display_name..."
        
        systemctl start "$service_name"
        
        if systemctl is-active --quiet "$service_name"; then
            print_status "$display_name started successfully."
        else
            print_error "Failed to start $display_name. Check logs: journalctl -u $service_name"
        fi
    fi
}

# Detect Dante Service Name
detect_dante_service() {
    if systemctl list-unit-files | grep -q danted.service; then
        echo "danted"
    elif systemctl list-unit-files | grep -q sockd.service; then
        echo "sockd"
    elif systemctl list-unit-files | grep -q dante.service; then
        echo "dante"
    else
        echo ""
    fi
}

# Main Logic
echo "=========================================="
echo "   Proxy Service Health Check"
echo "=========================================="

# 1. Check Squid
if systemctl list-unit-files | grep -q squid; then
    check_and_start_service "squid" "Squid Proxy"
else
    print_warning "Squid service not found on this system."
fi

# 2. Check Dante (SOCKS5)
DANTE_SERVICE=$(detect_dante_service)

if [ -n "$DANTE_SERVICE" ]; then
    check_and_start_service "$DANTE_SERVICE" "Dante SOCKS5 Proxy"
else
    print_warning "Dante/Sockd service not found on this system."
fi

echo "=========================================="
