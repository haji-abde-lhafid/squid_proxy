#!/usr/bin/env bash

# ==============================================================================
# Monitor Proxy Services
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/system_utils.sh" 2>/dev/null || true

monitor_proxy() {
    while true; do
        clear
        echo -e "${CYAN}${BOLD}==========================================${NC}"
        echo -e "${CYAN}${BOLD}         Live Proxy Monitor               ${NC}"
        echo -e "${CYAN}${BOLD}==========================================${NC}"
        echo -e "Press [Ctrl+C] to exit..."
        echo ""
        
        # System Stats
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
        local mem_info=$(free -m)
        local mem_used=$(echo "$mem_info" | awk '/^Mem:/{print $3}')
        local mem_total=$(echo "$mem_info" | awk '/^Mem:/{print $2}')
        local mem_perc=$(awk "BEGIN {printf \"%.2f\", ($mem_used/$mem_total)*100}")
        local disk_usage=$(df -h / | awk 'NR==2 {print $5}')
        
        echo -e "${BOLD}--- System ---${NC}"
        echo -e "CPU Usage : ${cpu_usage}%"
        echo -e "RAM Usage : ${mem_used}MB / ${mem_total}MB (${mem_perc}%)"
        echo -e "Disk Usage: ${disk_usage}"
        echo ""
        
        # Network Connections
        echo -e "${BOLD}--- Network ---${NC}"
        local total_conn=$(ss -s | awk '/TCP:/{print $2}')
        echo -e "Total TCP Connections: $total_conn"
        
        # Squid Stats
        if systemctl is-active squid &>/dev/null; then
            echo -e "\n${BOLD}--- Squid Proxy ---${NC}"
            local squid_conn=$(ss -tn state established '( sport = :3128 )' | wc -l)
            local squid_conn=$((squid_conn - 1))
            [[ $squid_conn -lt 0 ]] && squid_conn=0
            echo -e "Active Connections: $squid_conn"
            echo -e "Status: ${GREEN}Running${NC}"
        fi
        
        # Dante Stats
        local dante_svc=""
        if systemctl list-unit-files | grep -q "^dante-server"; then
            dante_svc="dante-server"
        elif systemctl list-unit-files | grep -q "^danted"; then
            dante_svc="danted"
        fi
        
        if [[ -n "$dante_svc" ]] && systemctl is-active "$dante_svc" &>/dev/null; then
            echo -e "\n${BOLD}--- Dante Proxy ---${NC}"
            local dante_conn=$(ss -tn state established '( sport = :1080 )' | wc -l)
            local dante_conn=$((dante_conn - 1))
            [[ $dante_conn -lt 0 ]] && dante_conn=0
            echo -e "Active Connections: $dante_conn"
            echo -e "Status: ${GREEN}Running${NC}"
        fi
        
        sleep 1
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    monitor_proxy
fi
