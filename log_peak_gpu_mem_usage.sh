#!/bin/bash

# Log file
LOG_FILE="/home/garner/Documents/scripts/resource_log_scripts/gpu_peak_mem_usage.log"

# Initialize peak memory usage
PEAK_MEMORY_USAGE=0
PEAK_MEMORY_PROCESSES=""

# Function to log peak memory usage and processes
log_peak_memory_usage() {
    while true; do
        CURRENT_MEMORY_USAGE=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | awk '{print $1}')
        if (( CURRENT_MEMORY_USAGE > PEAK_MEMORY_USAGE )); then
            # Update peak memory usage
            PEAK_MEMORY_USAGE=$CURRENT_MEMORY_USAGE
            PEAK_MEMORY_PROCESSES=$(nvidia-smi | grep -A1000 "Processes")
            
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            
            # Log peak memory usage
            echo "Peak Memory Usage: $PEAK_MEMORY_USAGE MiB at $TIMESTAMP" > "$LOG_FILE"

            # Log processes using GPU memory at peak usage
            echo "Processes using GPU memory at peak usage:" >> "$LOG_FILE"
            echo "$PEAK_MEMORY_PROCESSES" >> "$LOG_FILE"
        fi
        sleep 0.1  # Adjust sleep time as needed
    done
}

# Call the function to start logging peak memory usage
log_peak_memory_usage

