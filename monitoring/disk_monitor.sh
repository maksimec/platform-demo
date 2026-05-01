#!/bin/bash
set -e

LOG_DIR="/var/log/monitor"
LOG_FILE="${LOG_DIR}/disk_monitor.log"
THRESHOLD=80

if [ ! -d "${LOG_DIR}" ]; then
    echo "Error: Directory ${LOG_DIR} does not exist." >&2
    exit 1
fi

DISK_USAGE=$(df -P /hostfs | awk 'NR==2 {gsub("%","",$5); print $5}')

if ! [[ "${DISK_USAGE}" =~ ^[0-9]+$ ]]; then
    echo "Error: Failed to retrieve disk usage. Value: '${DISK_USAGE}'" >&2
    exit 1
fi

if [ "${DISK_USAGE}" -gt "${THRESHOLD}" ]; then
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] WARNING: Disk usage at ${DISK_USAGE}%" >> "${LOG_FILE}"
fi
