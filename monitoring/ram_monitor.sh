#!/bin/bash
set -e

LOG_DIR="/var/log/monitor"
LOG_FILE="${LOG_DIR}/ram_monitor.log"
THRESHOLD=85
MEMINFO="/host_proc/meminfo"

if [ ! -d "${LOG_DIR}" ]; then
    echo "Error: Directory ${LOG_DIR} does not exist." >&2
    exit 1
fi

if [ ! -r "${MEMINFO}" ]; then
    echo "Error: Cannot read ${MEMINFO}." >&2
    exit 1
fi

TOTAL_KB=$(awk '/MemTotal:/ {print $2}' "${MEMINFO}")
AVAIL_KB=$(awk '/MemAvailable:/ {print $2}' "${MEMINFO}")

if ! [[ "${TOTAL_KB}" =~ ^[0-9]+$ ]] || ! [[ "${AVAIL_KB}" =~ ^[0-9]+$ ]]; then
    echo "Error: Failed to retrieve RAM usage correctly." >&2
    exit 1
fi

if [ "${TOTAL_KB}" -eq 0 ]; then
    echo "Error: Total RAM is reported as 0." >&2
    exit 1
fi

USED_KB=$(( TOTAL_KB - AVAIL_KB ))
PERCENTAGE=$(( USED_KB * 100 / TOTAL_KB ))

if [ "${PERCENTAGE}" -gt "${THRESHOLD}" ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    TOTAL_G=$(awk "BEGIN {printf \"%.1f\", ${TOTAL_KB}/1048576}")
    USED_G=$(awk "BEGIN {printf \"%.1f\", ${USED_KB}/1048576}")
    echo "[$TIMESTAMP] WARNING: RAM usage at ${PERCENTAGE}% (${USED_G}G/${TOTAL_G}G used)" >> "${LOG_FILE}"
fi
