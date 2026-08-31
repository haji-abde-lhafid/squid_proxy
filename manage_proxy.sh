#!/usr/bin/env bash

# ==============================================================================
# Master Proxy Management Script
# ==============================================================================

# Ensure we are in the correct directory
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

# Repository details
REPO_URL="https://raw.githubusercontent.com/haji-abde-lhafid/squid_proxy/main"
FILES=("common.sh" "system_utils.sh" "network_utils.sh" "user_manager.sh" "install_squid.sh" "install_dante.sh" "install_squid_dante.sh" "optimize_proxy.sh" "benchmark_proxy.sh" "uninstall_squid.sh" "uninstall_dante.sh" "repair_proxy.sh" "monitor_proxy.sh" "clear_cache.sh")

# Download files every time
echo "Downloading required files from repository..."
for file in "${FILES[@]}"; do
    curl -s -O "$REPO_URL/$file" || wget -q "$REPO_URL/$file"
    chmod +x "$file" 2>/dev/null || true
done

source "common.sh"
source "user_manager.sh"
source "system_utils.sh"

# Execute a subscript
run_script() {
    local script="$1"
    local args="${2:-}"
    
    if [[ -f "$script" ]]; then
        if [[ -n "$args" ]]; then
            bash "$script" "$args"
        else
            bash "$script"
        fi
        echo ""
        read -r -p "Press Enter to continue..."
    else
        print_error "Script $script not found!"
        sleep 2
    fi
}

manage_users_menu() {
    while true; do
        show_header
        echo -e "${CYAN}${BOLD}--- User Management ---${NC}"
        echo -e "${YELLOW}1)${NC} Add User"
        echo -e "${YELLOW}2)${NC} Delete User"
        echo -e "${YELLOW}3)${NC} List Users"
        echo -e "${YELLOW}4)${NC} Change Password"
        echo -e "${BOLD}0)${NC} Back to Main Menu"
        echo ""
        read -r -p "Enter choice [0-4]: " uchoice
        case $uchoice in
            1) add_user; read -r -p "Press Enter to continue..." ;;
            2) delete_user; read -r -p "Press Enter to continue..." ;;
            3) list_users; read -r -p "Press Enter to continue..." ;;
            4) change_password; read -r -p "Press Enter to continue..." ;;
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
            1) run_script "install_squid_dante.sh" ;;
            2) 
                if prompt_confirm "Are you sure you want to uninstall EVERYTHING?" "N"; then
                    bash "uninstall_squid.sh"
                    bash "uninstall_dante.sh"
                    echo ""
                    read -r -p "Press Enter to continue..."
                fi
                ;;
            3) run_script "monitor_proxy.sh" ;;
            4) run_script "clear_cache.sh" ;;
            5) manage_users_menu ;;
            0) 
                print_info "Exiting..."
                exit 0 
                ;;
            *) 
                print_error "Invalid choice."
                sleep 1
                ;;
        esac
    done
}

# Verify root before starting menu
check_root

main_menu
