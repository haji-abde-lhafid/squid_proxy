#!/bin/bash

# check_proxy_services.sh
# Checks if Squid and Dante (Socks) services are running, and starts them if they are not.
# Can be run via cron (e.g., every 5 minutes).

LOG_FILE="/var/log/proxy_monitor.log"
TOUCH_LOG=true

# Ensure log file exists and is writable if we are root
if [ "$EUID" -eq 0 ] && [ "$TOUCH_LOG" = true ]; then
    touch "$LOG_FILE" 2>/dev/null || TOUCH_LOG=false
else
    TOUCH_LOG=false
fi

log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    if [ "$TOUCH_LOG" = true ] && [ -w "$LOG_FILE" ]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

check_systemd_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        # Service is running, do nothing (or log debug)
        return 0
    else
        log_msg "ALERT: Service '$service' is DOWN. Attempting to start..."
        systemctl start "$service"
        if systemctl is-active --quiet "$service"; then
            log_msg "SUCCESS: Service '$service' has been started."
        else
            log_msg "ERROR: Failed to start service '$service'. Check logs for details."
        fi
    fi
}

check_sysv_service() {
    local service=$1
    if service "$service" status >/dev/null 2>&1; then
        return 0
    else
        log_msg "ALERT: Service '$service' is DOWN. Attempting to start..."
        service "$service" start
        # Re-check
        if service "$service" status >/dev/null 2>&1; then
             log_msg "SUCCESS: Service '$service' has been started."
        else
             log_msg "ERROR: Failed to start service '$service'."
        fi
    fi
}

check_openrc_service() {
    local service=$1
    if rc-service "$service" status >/dev/null 2>&1; then
         return 0
    else
        log_msg "ALERT: Service '$service' is DOWN. Attempting to start..."
        rc-service "$service" start
        if rc-service "$service" status >/dev/null 2>&1; then
             log_msg "SUCCESS: Service '$service' has been started."
        else
             log_msg "ERROR: Failed to start service '$service'."
        fi
    fi
}

# Main Logic
log_msg "Checking proxy services..."

# Detect Init System
if command -v systemctl &> /dev/null; then
    # Systemd
    check_systemd_service "squid"
    
    if systemctl list-unit-files | grep -q "danted.service"; then
        check_systemd_service "danted"
    elif systemctl list-unit-files | grep -q "sockd.service"; then
        check_systemd_service "sockd"
    fi

elif [ -f /etc/init.d/squid ]; then
    # SysVinit
    check_sysv_service "squid"
    
    if [ -f /etc/init.d/danted ]; then
        check_sysv_service "danted"
    elif [ -f /etc/init.d/sockd ]; then
        check_sysv_service "sockd"
    fi

elif command -v rc-service &> /dev/null; then
    # OpenRC (Alpine)
    check_openrc_service "squid"
    
    if rc-service -l | grep -q "dante"; then
        check_openrc_service "dante"
    elif rc-service -l | grep -q "sockd"; then
         check_openrc_service "sockd"
    fi
else
    log_msg "ERROR: Could not detect service manager (systemd, sysvinit, or openrc)."
    exit 1
fi

log_msg "Check complete."
