#!/bin/bash
set -o pipefail

LOG_DIR="/var/log/monitor"
DISK_LOG="${LOG_DIR}/disk_monitor.log"
RAM_LOG="${LOG_DIR}/ram_monitor.log"
EMAIL_LOG="${LOG_DIR}/email_notifications.log"
HOSTNAME=$(hostname)

if [ ! -d "${LOG_DIR}" ]; then
    echo "Error: Directory ${LOG_DIR} does not exist." >&2
    exit 1
fi

touch "${DISK_LOG}" "${RAM_LOG}" "${EMAIL_LOG}"

tail -F "${DISK_LOG}" "${RAM_LOG}" | while read -r line; do
    if echo "${line}" | grep -q "WARNING"; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        MESSAGE="[$TIMESTAMP] Host: ${HOSTNAME} - Event: ${line}"
        echo "${MESSAGE}" >> "${EMAIL_LOG}"
    fi
done
