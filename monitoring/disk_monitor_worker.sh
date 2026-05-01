#!/bin/bash
set -e

while true; do
    /usr/local/bin/disk_monitor.sh
    sleep 60
done
