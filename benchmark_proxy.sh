#!/usr/bin/env bash

# ==============================================================================
# Benchmark Proxy Latency and Concurrency
# ==============================================================================

source "$(dirname "$0")/common.sh" 2>/dev/null || true
source "$(dirname "$0")/network_utils.sh" 2>/dev/null || true

TARGET_URL="https://httpbin.org/ip"
CONCURRENCY=10

format_curl_timing() {
    local proxy_type="$1"
    local proxy_url="$2"
    local user_pass="$3"
    
    print_info "Measuring detailed timing for $proxy_type ($proxy_url)..."
    
    local curl_cmd=(curl -s -o /dev/null -w "DNS Lookup: %{time_namelookup}s\nTCP Connect: %{time_connect}s\nApp Connect: %{time_appconnect}s\nPre-transfer: %{time_pretransfer}s\nTTFB: %{time_starttransfer}s\nTotal Time: %{time_total}s\nHTTP Code: %{http_code}\n" --max-time 10)
    
    if [[ "$proxy_type" == "HTTP" ]]; then
        if [[ -n "$user_pass" ]]; then
            curl_cmd+=("-x" "http://${user_pass}@${proxy_url}")
        else
            curl_cmd+=("-x" "http://${proxy_url}")
        fi
    elif [[ "$proxy_type" == "SOCKS5" ]]; then
        if [[ -n "$user_pass" ]]; then
            curl_cmd+=("-x" "socks5h://${user_pass}@${proxy_url}")
        else
            curl_cmd+=("-x" "socks5h://${proxy_url}")
        fi
    fi
    
    curl_cmd+=("$TARGET_URL")
    
    local result
    local status
    result=$("${curl_cmd[@]}" 2>&1)
    status=$?
    
    if [[ $status -eq 0 && $(echo "$result" | grep "HTTP Code: 200") ]]; then
        echo -e "${GREEN}--- Single Request Timing Metrics ($proxy_type) ---${NC}"
        echo "$result"
    else
        print_error "Request via $proxy_type proxy failed or returned non-200 status."
        echo "$result"
    fi
}

benchmark_concurrency() {
    local proxy_type="$1"
    local proxy_url="$2"
    local user_pass="$3"
    local count="${4:-$CONCURRENCY}"
    
    print_info "Starting concurrent request benchmark ($count parallel requests) for $proxy_type..."
    
    local tmp_dir
    tmp_dir=$(mktemp -d)
    local start_time
    start_time=$(date +%s%3N)
    
    for i in $(seq 1 "$count"); do
        (
            local curl_cmd=(curl -s -o /dev/null -w "%{http_code} %{time_total}\n" --max-time 15)
            if [[ "$proxy_type" == "HTTP" ]]; then
                if [[ -n "$user_pass" ]]; then
                    curl_cmd+=("-x" "http://${user_pass}@${proxy_url}")
                else
                    curl_cmd+=("-x" "http://${proxy_url}")
                fi
            elif [[ "$proxy_type" == "SOCKS5" ]]; then
                if [[ -n "$user_pass" ]]; then
                    curl_cmd+=("-x" "socks5h://${user_pass}@${proxy_url}")
                else
                    curl_cmd+=("-x" "socks5h://${proxy_url}")
                fi
            fi
            curl_cmd+=("$TARGET_URL")
            
            "${curl_cmd[@]}" > "$tmp_dir/req_$i.txt" 2>&1
        ) &
    done
    
    wait
    
    local end_time
    end_time=$(date +%s%3N)
    local elapsed_ms=$((end_time - start_time))
    local elapsed_sec
    elapsed_sec=$(awk "BEGIN {print $elapsed_ms/1000}")
    
    local success_count=0
    local fail_count=0
    local total_time_sum=0
    
    for f in "$tmp_dir"/req_*.txt; do
        if [[ -f "$f" ]]; then
            read -r code ttime < "$f"
            if [[ "$code" == "200" ]]; then
                ((success_count++))
                total_time_sum=$(awk "BEGIN {print $total_time_sum + ${ttime:-0}}")
            else
                ((fail_count++))
            fi
        fi
    done
    
    rm -rf "$tmp_dir"
    
    local avg_req_time=0
    if [[ $success_count -gt 0 ]]; then
        avg_req_time=$(awk "BEGIN {print $total_time_sum / $success_count}")
    fi
    
    echo -e "${GREEN}--- Concurrency Benchmark Summary ($proxy_type) ---${NC}"
    echo -e "Total Requests Sent: $count"
    echo -e "Successful (200 OK): ${GREEN}$success_count${NC}"
    echo -e "Failed / Timed Out:  ${RED}$fail_count${NC}"
    echo -e "Total Batch Duration: ${YELLOW}${elapsed_sec}s${NC}"
    echo -e "Avg Time / Request:  ${CYAN}${avg_req_time}s${NC}"
}

run_benchmark() {
    show_header
    print_info "Starting Proxy Latency & Concurrency Benchmark Utility"
    
    local http_host="${1:-}"
    local socks_host="${2:-}"
    local auth="${3:-}"
    
    # Prompt for authentication if not supplied
    if [[ -z "$auth" ]]; then
        echo ""
        read -r -p "Enter proxy username (leave empty if no auth): " puser
        if [[ -n "$puser" ]]; then
            read -r -s -p "Enter proxy password: " ppass
            echo ""
            auth="${puser}:${ppass}"
        fi
    fi
    
    if [[ -z "$http_host" ]]; then
        http_host="127.0.0.1:3128"
    fi
    if [[ -z "$socks_host" ]]; then
        socks_host="127.0.0.1:1080"
    fi
    
    echo ""
    echo "=========================================="
    echo " 1. Testing Squid (HTTP) Proxy ($http_host)"
    echo "=========================================="
    format_curl_timing "HTTP" "$http_host" "$auth"
    echo ""
    benchmark_concurrency "HTTP" "$http_host" "$auth" 10
    
    echo ""
    echo "=========================================="
    echo " 2. Testing Dante (SOCKS5) Proxy ($socks_host)"
    echo "=========================================="
    format_curl_timing "SOCKS5" "$socks_host" "$auth"
    echo ""
    benchmark_concurrency "SOCKS5" "$socks_host" "$auth" 10
    
    echo ""
    print_success "Benchmark completed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_benchmark "$@"
fi
