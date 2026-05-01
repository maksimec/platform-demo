#!/bin/bash
set -e

while true; do
    /usr/local/bin/ram_monitor.sh
    sleep 60
done
