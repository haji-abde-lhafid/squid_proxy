#!/bin/bash

# clear_logs.sh
# Script to clear Squid and Dante proxy logs

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root"
    exit 1
fi

print_info "Clearing proxy logs..."

# Clear Squid logs
if [ -d "/var/log/squid" ]; then
    print_info "Clearing Squid logs..."
    > /var/log/squid/access.log
    > /var/log/squid/cache.log
    print_success "Squid logs cleared."
else
    print_info "Squid log directory not found. Skipping Squid logs."
fi

# Clear Dante logs
print_info "Clearing Dante logs..."
files_cleared=0
for logfile in /var/log/sockd*.log; do
    if [ -f "$logfile" ]; then
        > "$logfile"
        print_success "Cleared $logfile"
        files_cleared=$((files_cleared + 1))
    fi
done

if [ "$files_cleared" -eq 0 ]; then
    print_info "No Dante logs found."
fi

print_success "Proxy logs clearance process completed."
