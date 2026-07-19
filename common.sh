#!/usr/bin/env bash

# ==============================================================================
# Common Utilities
# ==============================================================================

# Constants
readonly LOG_FILE="/var/log/proxy-manager.log"
readonly SQUID_DIR="/etc/squid"
readonly DANTE_CONF="/etc/sockd.conf"
readonly PASSWD_FILE="/etc/squid/passwd"
readonly BACKUP_DIR="/var/backups/proxy-manager"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Initialize Log File
init_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE" 2>/dev/null || true
        chmod 644 "$LOG_FILE" 2>/dev/null || true
    fi
}

log_msg() {
    local type="$1"
    local msg="$2"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$ts] [$type] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Print status messages
print_info() {
    echo -e "${BLUE}[*]${NC} $1"
    log_msg "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    log_msg "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    log_msg "WARN" "$1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    log_msg "ERROR" "$1"
}

# Error Handler
check_result() {
    local status=$?
    local success_msg="$1"
    local error_msg="$2"
    local allow_fail="${3:-false}"

    if [[ $status -eq 0 ]]; then
        print_success "$success_msg"
        return 0
    else
        print_error "$error_msg"
        if [[ "$allow_fail" == "false" ]]; then
            echo -e "${RED}Fatal error encountered. Exiting.${NC}"
            exit 1
        fi
        return 1
    fi
}

# Execute command silently but log it
execute_cmd() {
    local msg="$1"
    shift
    local cmd=("$@")
    
    echo -en "${BLUE}[*]${NC} $msg... "
    log_msg "CMD" "${cmd[*]}"
    
    local output
    if output=$("${cmd[@]}" 2>&1); then
        echo -e "${GREEN}Done${NC}"
        log_msg "SUCCESS" "Command succeeded"
        return 0
    else
        echo -e "${RED}Failed${NC}"
        log_msg "ERROR" "Command failed: ${cmd[*]}"
        log_msg "OUTPUT" "$output"
        return 1
    fi
}

show_header() {
    clear
    echo -e "${CYAN}${BOLD}==========================================${NC}"
    echo -e "${CYAN}${BOLD}           Proxy Management               ${NC}"
    echo -e "${CYAN}${BOLD}==========================================${NC}"
    echo ""
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local reply
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -r -p "$prompt" reply
    if [[ -z "$reply" ]]; then
        reply="$default"
    fi
    
    case "$reply" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

init_log
