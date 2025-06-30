#!/bin/bash

# ============================================
# Wifi Sniffer - Client Traffic Visualization
# ============================================

# ====== CONFIGURATION ======
LOG_FILE="/var/log/dnsmasq.log"      # Path to dnsmasq log file
TIMEFRAME_MINUTES=60                 # Minutes to look back for queries
MAX_DOMAINS=20                       # Number of domains to show per client
REFRESH_INTERVAL=1                   # Live refresh interval (seconds)
TAIL_LINES=25000                     # Lines to cache for parsing (performance tuning)
TMP_RAM_LOG="/dev/shm/wifisniff_recent.log" # Fast temp log in RAM

# ====== COLORS ======
NC='\033[0m'
BOLD='\033[1m'
CYAN='\033[36m'
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
WHITE='\033[37m'
GREY='\033[90m'

# ========== CHECK DEPENDENCIES ==========
for dep in tail awk grep sort cut date tput; do
    command -v $dep >/dev/null 2>&1 || { echo -e "${RED}[ERROR]${NC} Required tool '$dep' not found."; exit 1; }
done

# ========== ERROR HANDLING FOR LOGFILE ==========
if [[ ! -e "$LOG_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} Log file $LOG_FILE does not exist!"
    exit 1
fi
if [[ ! -r "$LOG_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} Log file $LOG_FILE is not readable (check permissions)."
    exit 1
fi
if [[ ! -d "/dev/shm" ]]; then
    echo -e "${RED}[ERROR]${NC} /dev/shm (RAM-Disk) not available. Please check your system."
    exit 1
fi

# ========== LOGFILE MONITOR (background tail -F) ==========
# Function: Monitors the real log file and always writes the last TAIL_LINES lines to the RAM log.
start_log_monitor() 
{
    # If already running stop and start new monitor in the background
    pkill -f "tail -F $LOG_FILE" 2>/dev/null
    ( tail -F "$LOG_FILE" 2>/dev/null | stdbuf -oL grep --line-buffered -E "query\[|from " >> "$TMP_RAM_LOG" ) &
    LOG_MON_PID=$!
    # Keep only last $TAIL_LINES lines (memory efficiency)
    ( while sleep 3; do
        tail -n $TAIL_LINES "$TMP_RAM_LOG" > "${TMP_RAM_LOG}.tmp" && mv "${TMP_RAM_LOG}.tmp" "$TMP_RAM_LOG"
    done ) &
    TRIM_PID=$!
}
cleanup_monitor() 
{
    [[ $LOG_MON_PID ]] && kill $LOG_MON_PID 2>/dev/null
    [[ $TRIM_PID ]] && kill $TRIM_PID 2>/dev/null
    rm -f "$TMP_RAM_LOG"
}
trap cleanup_monitor EXIT

# ========== TERMINAL SIZE DETECTION ==========
get_terminal_width() 
{
    local width
    width=$(tput cols 2>/dev/null)
    [[ -z "$width" || "$width" -lt 60 ]] && width=80
    echo "$width"
}

# =========================
# Utility: Get epoch for dnsmasq syslog timestamp
# =========================
get_epoch() 
{
    date --date="$1 $(date +%Y)" +%s 2>/dev/null
}

# =========================
# Parse log file for queries in the timeframe, keep in memory (performance: only RAM-log)
# Out: prints "client_ip|domain|last_seen_epoch|count"
# =========================
parse_log() 
{
    local now
    now=$(date +%s)
    awk -v mins="$TIMEFRAME_MINUTES" -v now="$now" '
    BEGIN{
        split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec",months," ");
        for(i=1;i<=12;i++) m[months[i]]=i;
    }
    /query\[/ && /from / {
        ts_str = $1 " " $2 " " $3;
        cmd = "date --date=\"" ts_str " " strftime("%Y") "\" +%s";
        cmd | getline ts;
        close(cmd);
        if(now-ts<=mins*60 && match($0,/query\[.*\] ([^ ]+) from ([0-9.]+)$/,arr)){
            dom=arr[1];
            ip=arr[2];
            key=ip"|"dom;
            count[key]++;
            last_seen[key]=ts;
            client_last[ip]=((!client_last[ip]||client_last[ip]<ts)?ts:client_last[ip]);
        }
    }
    END{
        for(key in count){
            split(key, arr, "|");
            ip=arr[1]; dom=arr[2];
            print ip "|" dom "|" last_seen[key] "|" count[key];
        }
        for(ip in client_last){
            print "CLIENT|"ip"|"client_last[ip];
        }
    }
    ' "$TMP_RAM_LOG"
}

# =========================
# UI: Print banner/header
# =========================
print_banner() 
{
    local width
    width=$(get_terminal_width)
    printf "${BOLD}${CYAN}%*s${NC}\n" $(( (width + 34) / 2 )) "==========================================="
    printf "${BOLD}${CYAN}%*s${NC}\n" $(( (width + 30) / 2 )) "  Wifi Sniffer - Client Traffic Monitor "
    printf "${BOLD}${CYAN}%*s${NC}\n" $(( (width + 34) / 2 )) "==========================================="
}

# =========================
# UI: Live-Client selection menu
# =========================
select_client_live() 
{
    declare -A CLIENTS
    local sel="" last_displayed=""
    while true; do
        # Parse and show again (from RAM-Logfile)
        CLIENTS=()
        local i=1 parsed_data display clients_found=0

        parsed_data=$(parse_log)
        clear
        print_banner

        mapfile -t client_lines < <(echo "$parsed_data" | grep "^CLIENT|")
        if [[ ${#client_lines[@]} -eq 0 ]]; then
            echo -e "${RED}No active clients in the last $TIMEFRAME_MINUTES minutes.${NC}"
        else
            # Sort by last activity
            sorted=($(for line in "${client_lines[@]}"; do
                ip=$(echo "$line" | cut -d"|" -f2)
                ts=$(echo "$line" | cut -d"|" -f3)
                echo "$ts|$ip"
            done | sort -rn | cut -d"|" -f2))
        
            # Print the clients
            for ip in "${sorted[@]}"; do
                CLIENTS[$i]=$ip
                printf "${BLUE}%2d)${NC} ${GREEN}%s${NC}\n" "$i" "$ip"
                ((i++))
            done
        
            clients_found=1
        fi
        
        echo -e "${MAGENTA} q) Quit${NC}\n"
        
        # Only show the client selection if a client is visible
        [[ "$clients_found" -eq 1 ]] && echo -en "${YELLOW}Select client number: ${NC}"
        
        # Wait for user input and reload the ui of nothing has been entered
        read -t "$REFRESH_INTERVAL" -n 1 sel
        
        if [[ -n "$sel" ]]; then
            if [[ "$sel" == "q" ]]; then exit 0; fi

            if [[ ! "$sel" =~ ^[0-9]+$ ]] || [[ -z "${CLIENTS[$sel]}" ]]; then
                echo -e "${RED}Invalid selection.${NC}"; sleep 1
                continue
            fi
            
            SELECTED_CLIENT="${CLIENTS[$sel]}"
            return 0
        fi
    done
}

# =========================
# UI: Show domain table for selected client
# =========================
show_client_domains() 
{
    local client_ip="$1" width dom_col cnt_col time_col dom ts cnt time_human color

    # Resize the screen so the therminal can be moved
    width=$(get_terminal_width)
    ((dom_col=width-30))
    ((dom_col<20)) && dom_col=20
    cnt_col=8; time_col=10

    # Parse the data in a usable manner
    local parsed_data
    parsed_data=$(parse_log)
    mapfile -t domains < <(echo "$parsed_data" | awk -F'|' -v ip="$client_ip" '
        $1==ip { print $2 "|" $3 "|" $4 }
    ' | sort -t"|" -k2,2nr | head -n $MAX_DOMAINS)

    # Print the headline of the table
    clear
    print_banner
    echo -e "${BOLD}${CYAN}DNS queries for client: ${GREEN}${client_ip}${CYAN} (last $TIMEFRAME_MINUTES min)${NC}\n"
    printf "${BOLD}${WHITE}%-${dom_col}s %-${cnt_col}s %-${time_col}s${NC}\n" "Domain" "Count" "Last Seen"
    printf "${GREY}%s${NC}\n" "$(printf '─%.0s' $(seq 1 $width))"

    # Print the DNS queries in the table
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo -e "${RED}No DNS queries from this client in the last $TIMEFRAME_MINUTES minutes.${NC}"
    else
        for entry in "${domains[@]}"; do
            dom=$(echo "$entry" | cut -d"|" -f1)
            ts=$(echo "$entry" | cut -d"|" -f2)
            cnt=$(echo "$entry" | cut -d"|" -f3)
    
            # Truncate domain if too wide
            [[ ${#dom} -gt $((dom_col-3)) ]] && dom="${dom:0:$((dom_col-3))}..."
            time_human=$(date -d @"$ts" "+%H:%M:%S")
            color="$GREEN"
            printf "${color}%-${dom_col}s${CYAN} %-${cnt_col}s ${GREY}%-${time_col}s${NC}\n" "$dom" "$cnt" "$time_human"
        done
    fi
    
    echo -e "\n${MAGENTA}[Any key: back to client selection | ${CYAN}Ctrl+C to exit${MAGENTA}]${NC}"
}

# =========================
# MAIN LOGIC WITH RAM-CACHE MONITOR
# =========================

# Initial RAM-log snapshot (tail only last TAIL_LINES)
tail -n $TAIL_LINES "$LOG_FILE" > "$TMP_RAM_LOG"
start_log_monitor

while true; do
    SELECTED_CLIENT=""
    select_client_live
    while true; do
        show_client_domains "$SELECTED_CLIENT"
        read -t "$REFRESH_INTERVAL" -n 1 key && break
    done
done
