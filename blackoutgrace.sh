#!/usr/bin/env bash

set -euo pipefail

LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

# Load configuration from file
CONFIG_FILE="/etc/blackoutgrace.conf"
[[ ! -f "$CONFIG_FILE" ]] && { echo "$LOG_PREFIX Error: Configuration file not found"; exit 1; }

# Read config
eval "$(awk '/^\[general\]/{f=1;next} /^\[/{f=0} f && /^[^#]/ && /=/ {print $0}' \"$CONFIG_FILE\")"

# Set variables with defaults
BATTERY_FILE="${battery_file:-/tmp/blackoutgrace_battery_timestamp}"
SHUTDOWN_FLAG="${shutdown_flag:-/tmp/blackoutgrace_shutdown_initiated}"  
STATUS_FILE="${status_file:-/tmp/blackoutgrace_last_status_update}"
AC_RESTORE_FILE="${ac_restore_file:-/tmp/blackoutgrace_ac_restore_timestamp}"
MINUTES="${minutes:-25}"
SLEEP_INTERVAL="${sleep_interval:-5}"
STATUS_INTERVAL="${status_interval:-120}"
MIN_BATTERY="${min_battery:-10}"
AC_STABLE_TIME="${ac_stable_time:-300}"

# path validation
[[ ! -x "$(command -v ssh)" ]] && {
    echo "$LOG_PREFIX Error: ssh command not found"
    exit 1
}

# SSH key validation
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    echo "$LOG_PREFIX Error: SSH agent not running"
    exit 1
fi

# Signal handling
cleanup() {
    [[ -f "$BATTERY_FILE" ]] && rm -f "$BATTERY_FILE"
    [[ -f "$SHUTDOWN_FLAG" ]] && rm -f "$SHUTDOWN_FLAG"
    [[ -f "$AC_RESTORE_FILE" ]] && rm -f "$AC_RESTORE_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

check_power_state() {
    # Check both battery and AC adapter status
    local ac_state
    ac_state=$(acpi -a 2>/dev/null | grep -q "on-line" && echo "yes" || echo "no")
    
    if [ "$ac_state" = "yes" ]; then
        return 0  # AC power connected
    fi
    return 1     # On battery
}

initiate_shutdown() {
    local user=$1
    local host=$2
    if [[ ! -f "$SHUTDOWN_FLAG" ]]; then
        echo "$LOG_PREFIX Executing remote shutdown command on $host..."
        if timeout 30 ssh -o BatchMode=yes "$user@$host" "sudo poweroff"; then
            touch "$SHUTDOWN_FLAG"
            echo "$LOG_PREFIX Remote shutdown command sent successfully to $host"
        else
            echo "$LOG_PREFIX Error: Failed to initiate remote shutdown on $host"
        fi
    fi
}

reset_state() {
    rm -f "$BATTERY_FILE" "$SHUTDOWN_FLAG" "$AC_RESTORE_FILE"
}

format_countdown() {
    local seconds=$1
    if [ "$seconds" -ge 60 ]; then
        local mins=$(( seconds / 60 ))
        local secs=$(( seconds % 60 ))
        echo "${mins}m ${secs}s"
    else
        echo "${seconds}s"
    fi
}

log_status() {
    local battery_pct=$1
    local power_state=$2
    echo "$LOG_PREFIX Status update: $power_state power ($battery_pct%)"
    date +%s > "$STATUS_FILE"
}

while true; do
    if ! command -v acpi >/dev/null 2>&1; then
        echo "$LOG_PREFIX Error: acpi command not found. Please install acpi package (e.g., 'sudo apt install acpi')"
        exit 1
    fi

    BATTERY_INFO=$(acpi -b) || {
        echo "$LOG_PREFIX Error: Failed to get battery info"
        sleep 60
        continue
    }

    BATTERY_PCT=$(echo "$BATTERY_INFO" | grep -P -o '[0-9]+(?=%)' | head -n1 || echo "0")
    [[ ! "$BATTERY_PCT" =~ ^[0-9]+$ ]] && BATTERY_PCT=0

    # Check if status update is needed
    CURRENT_TIME=$(date +%s)
    if [[ ! -f "$STATUS_FILE" ]] || (( CURRENT_TIME - $(cat "$STATUS_FILE" 2>/dev/null || echo 0) >= STATUS_INTERVAL )); then
        if check_power_state; then
            log_status "$BATTERY_PCT" "AC"
        else
            log_status "$BATTERY_PCT" "Battery"
        fi
    fi

    if ! check_power_state; then
        # On battery power - remove AC restore file if it exists
        [[ -f "$AC_RESTORE_FILE" ]] && rm -f "$AC_RESTORE_FILE"
        
        if [ "$BATTERY_PCT" -lt "$MIN_BATTERY" ]; then
            echo "$LOG_PREFIX Battery critically low (${BATTERY_PCT}%), initiating immediate shutdown"
            while IFS= read -r line; do
                if [[ $line =~ ^\[.*\]$ ]]; then
                    section=$line
                elif [[ $line =~ ^user= ]]; then
                    user=${line#*=}
                elif [[ $line =~ ^host= ]]; then
                    host=${line#*=}
                    initiate_shutdown "$user" "$host"
                fi
            done < "$CONFIG_FILE"
            sleep "$SLEEP_INTERVAL"
            continue
        fi

        if [[ ! -f "$BATTERY_FILE" ]]; then
            date +%s > "$BATTERY_FILE"
            echo "$LOG_PREFIX System switched to battery power ($BATTERY_PCT%). Shutdown in $MINUTES minute(s)"
        else
            START=$(cat "$BATTERY_FILE")
            NOW=$(date +%s)
            SECONDS_ELAPSED=$(( NOW - START ))
            SECONDS_REMAINING=$(( MINUTES * 60 - SECONDS_ELAPSED ))
            
            if [ "$SECONDS_ELAPSED" -ge $(( MINUTES * 60 )) ] && [ ! -f "$SHUTDOWN_FLAG" ]; then
                echo "$LOG_PREFIX Battery timeout reached. Initiating shutdown"
                while IFS= read -r line; do
                    if [[ $line =~ ^\[.*\]$ ]]; then
                        section=$line
                    elif [[ $line =~ ^user= ]]; then
                        user=${line#*=}
                    elif [[ $line =~ ^host= ]]; then
                        host=${line#*=}
                        initiate_shutdown "$user" "$host"
                    fi
                done < "$CONFIG_FILE"
            elif [ "$SECONDS_REMAINING" -gt 0 ]; then
                COUNTDOWN=$(format_countdown "$SECONDS_REMAINING")
                echo "$LOG_PREFIX On battery power ($BATTERY_PCT%). Shutdown in $COUNTDOWN unless power restored"
            fi
        fi
    else
        # On AC power
        if [[ -f "$BATTERY_FILE" ]] || [[ -f "$SHUTDOWN_FLAG" ]]; then
            # Check if we need to track AC restore time
            if [[ ! -f "$AC_RESTORE_FILE" ]]; then
                date +%s > "$AC_RESTORE_FILE"
                echo "$LOG_PREFIX Power restored ($BATTERY_PCT%). Waiting $(( AC_STABLE_TIME / 60 )) minutes for stable power before cancelling shutdown"
            else
                # Check if AC has been stable long enough
                AC_RESTORE_START=$(cat "$AC_RESTORE_FILE")
                NOW=$(date +%s)
                STABLE_SECONDS=$(( NOW - AC_RESTORE_START ))
                
                if [ "$STABLE_SECONDS" -ge "$AC_STABLE_TIME" ]; then
                    echo "$LOG_PREFIX AC power stable for $(( STABLE_SECONDS / 60 )) minutes. Cancelling pending shutdown"
                    reset_state
                else
                    REMAINING_SECONDS=$(( AC_STABLE_TIME - STABLE_SECONDS ))
                    REMAINING_TIME=$(format_countdown "$REMAINING_SECONDS")
                    echo "$LOG_PREFIX AC power stable for $(( STABLE_SECONDS / 60 ))m. Shutdown cancelled in $REMAINING_TIME if power remains stable"
                fi
            fi
        else
            # No pending shutdown, remove AC restore file if it exists
            [[ -f "$AC_RESTORE_FILE" ]] && rm -f "$AC_RESTORE_FILE"
        fi
    fi

    sleep "$SLEEP_INTERVAL"
done
