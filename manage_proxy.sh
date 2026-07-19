#!/usr/bin/env bash

# ==============================================================================
# Master Proxy Management Script
# ==============================================================================

# Ensure we are in the correct directory
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

source "common.sh" 2>/dev/null || true
source "user_manager.sh" 2>/dev/null || true
source "system_utils.sh" 2>/dev/null || true

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

main_menu() {
    while true; do
        show_header
        echo -e "${GREEN}1)${NC} Install Squid"
        echo -e "${GREEN}2)${NC} Install Dante"
        echo -e "${GREEN}3)${NC} Install Squid + Dante"
        echo -e "${GREEN}4)${NC} Install without Authentication (Squid+Dante)"
        echo -e "${YELLOW}5)${NC} Add User"
        echo -e "${YELLOW}6)${NC} Delete User"
        echo -e "${YELLOW}7)${NC} List Users"
        echo -e "${YELLOW}8)${NC} Change Password"
        echo -e "${YELLOW}9)${NC} Enable User"
        echo -e "${YELLOW}10)${NC} Disable User"
        echo -e "${BLUE}11)${NC} Monitor Connections"
        echo -e "${BLUE}12)${NC} Repair Installation"
        echo -e "${BLUE}13)${NC} Backup Configuration"
        echo -e "${BLUE}14)${NC} Restore Configuration"
        echo -e "${RED}15)${NC} Uninstall Squid"
        echo -e "${RED}16)${NC} Uninstall Dante"
        echo -e "${RED}17)${NC} Uninstall Everything"
        echo -e "${BOLD}0)${NC} Exit"
        echo ""
        
        read -r -p "Enter your choice: " choice
        
        case $choice in
            1) run_script "install_squid.sh" ;;
            2) run_script "install_dante.sh" ;;
            3) run_script "install_squid_dante.sh" ;;
            4) run_script "install_squid_dante.sh" "--no-auth" ;;
            5) add_user; read -r -p "Press Enter to continue..." ;;
            6) delete_user; read -r -p "Press Enter to continue..." ;;
            7) list_users; read -r -p "Press Enter to continue..." ;;
            8) change_password; read -r -p "Press Enter to continue..." ;;
            9) enable_user; read -r -p "Press Enter to continue..." ;;
            10) disable_user; read -r -p "Press Enter to continue..." ;;
            11) run_script "monitor_proxy.sh" ;;
            12) run_script "repair_proxy.sh" ;;
            13) run_script "backup_proxy.sh" ;;
            14) run_script "restore_proxy.sh" ;;
            15) run_script "uninstall_squid.sh" ;;
            16) run_script "uninstall_dante.sh" ;;
            17) 
                if prompt_confirm "Are you sure you want to uninstall EVERYTHING?" "N"; then
                    bash "uninstall_squid.sh"
                    bash "uninstall_dante.sh"
                    echo ""
                    read -r -p "Press Enter to continue..."
                fi
                ;;
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
