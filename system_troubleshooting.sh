#!/bin/bash

# Collection of system monitoring and troubleshooting scripts

###################
# RAID Monitor    #
###################
check_raid() {
    echo "=== RAID Analysis ==="

    # Check for software RAID (mdadm)
    echo "Software RAID Status:"
    if [ -e "/proc/mdstat" ]; then
        cat /proc/mdstat

        # Get detailed info for each MD device
        for md in $(awk '/md/ {print $1}' /proc/mdstat 2>/dev/null); do
            echo -e "\nDetailed info for $md:"
            mdadm --detail "/dev/$md" 2>/dev/null

            # Check for degraded arrays
            if mdadm --detail "/dev/$md" | grep -q "degraded"; then
                echo "WARNING: $md is in degraded state!"
                echo "Checking rebuild status:"
                grep "recovery\|resync" /proc/mdstat
            fi
        done
    else
        echo "No MD RAID devices found"
    fi

    # Check for hardware RAID controllers
    echo -e "\nHardware RAID Controllers:"

    # LSI/Broadcom MegaRAID
    if command -v megacli &>/dev/null; then
        echo "MegaRAID Status:"
        megacli -LDInfo -Lall -aALL 2>/dev/null || echo "No MegaRAID arrays found"
        echo "Physical Drives:"
        megacli -PDList -aALL 2>/dev/null
        echo "Battery Backup Unit:"
        megacli -AdpBbuCmd -aAll 2>/dev/null
    fi

    # HP Smart Array
    if command -v hpacucli &>/dev/null; then
        echo -e "\nHP Smart Array Status:"
        hpacucli ctrl all show config 2>/dev/null || echo "No HP Smart Array controllers found"
    fi

    # Dell PERC
    if command -v perccli64 &>/dev/null; then
        echo -e "\nDell PERC Status:"
        perccli64 /call show 2>/dev/null || echo "No Dell PERC controllers found"
    fi

    # Adaptec
    if command -v arcconf &>/dev/null; then
        echo -e "\nAdaptec RAID Status:"
        arcconf getconfig 1 2>/dev/null || echo "No Adaptec controllers found"
    fi

    # Check for ZFS RAID
    if command -v zpool &>/dev/null; then
        echo -e "\nZFS Pool Status:"
        zpool status
        echo -e "\nZFS Pool Health:"
        zpool list
        echo -e "\nZFS Pool I/O Statistics:"
        zpool iostat -v
    fi
}

###################
# Benchmarking    #
###################
run_benchmarks() {
    local benchmark_type=$1
    local duration=${2:-30}  # Default 30 seconds for tests

    echo "=== Performance Benchmarking ==="

    case $benchmark_type in
        "storage")
            echo "Storage Benchmark:"

            # Create temporary directory for testing
            TEST_DIR=$(mktemp -d)

            # Function to clean up test files
            cleanup() {
                rm -rf "$TEST_DIR"
            }
            trap cleanup EXIT

            echo "Running sequential read/write tests..."

            # Sequential write test using dd
            echo "Sequential Write Speed (dd):"
            dd if=/dev/zero of="$TEST_DIR/test_file" bs=1M count=1024 conv=fdatasync 2>&1 | grep -o "[0-9.]* GB/s\|[0-9.]* MB/s"

            # Sequential read test
            echo "Sequential Read Speed (dd):"
            dd if="$TEST_DIR/test_file" of=/dev/null bs=1M 2>&1 | grep -o "[0-9.]* GB/s\|[0-9.]* MB/s"

            # If fio is available, run more detailed tests
            if command -v fio &>/dev/null; then
                echo -e "\nRunning detailed FIO benchmarks..."

                # Random read/write test
                fio --name=random-rw \
                    --directory="$TEST_DIR" \
                    --size=512m \
                    --time_based \
                    --runtime="$duration" \
                    --ioengine=libaio \
                    --direct=1 \
                    --verify=0 \
                    --bs=4k \
                    --iodepth=64 \
                    --rw=randrw \
                    --rwmixread=75 \
                    --group_reporting
            fi

            # If iostat is available, monitor disk I/O during test
            if command -v iostat &>/dev/null; then
                echo -e "\nDisk I/O Statistics during test:"
                iostat -x 1 5
            fi
            ;;

        "graphics")
            echo "Graphics Benchmark:"

            # Check for glxgears (basic OpenGL benchmark)
            if command -v glxgears &>/dev/null; then
                echo "Running GLXGears benchmark for $duration seconds..."
                timeout "$duration" glxgears -info 2>&1 | grep "frames in"
            fi

            # Check for vblank test
            if command -v vblank_test &>/dev/null; then
                echo -e "\nChecking VBlank synchronization..."
                vblank_test
            fi

            # Check for Vulkan support and run vulkan-smoketest if available
            if command -v vulkaninfo &>/dev/null; then
                echo -e "\nVulkan Capability Test:"
                vulkaninfo --summary
            fi

            # If unigine-heaven is installed, run a basic benchmark
            if command -v unigine-heaven &>/dev/null; then
                echo -e "\nRunning Unigine Heaven benchmark..."
                unigine-heaven --benchmark
            fi

            # Monitor GPU statistics during test
            # TODO: Consider gpu-top or glxinfo
            if command -v nvidia-smi &>/dev/null; then
                echo -e "\nNVIDIA GPU Statistics during test:"
                nvidia-smi --query-gpu=utilization.gpu,utilization.memory,temperature.gpu --format=csv -l 1 -c "$duration"
            elif [ -d "/sys/class/drm" ]; then
                echo -e "\nNON-NVIDIA GPU Statistics during test:"
                for ((i=0; i<duration; i++)); do
                    if [ -f "/sys/class/drm/card0/device/gpu_busy_percent" ]; then
                        cat /sys/class/drm/card0/device/gpu_busy_percent
                    fi
                    sleep 1
                done
            fi
            ;;

        "system")
            echo "System Benchmark:"

            # CPU stress test
            if command -v stress-ng &>/dev/null; then
                echo "Running CPU stress test..."
                stress-ng --cpu 4 --timeout "$duration"s --metrics
            fi

            # Memory benchmark
            if command -v mbw &>/dev/null; then
                echo -e "\nMemory bandwidth test:"
                mbw 1024
            fi

            # System load monitoring during tests
            echo -e "\nSystem metrics during test:"
            top -b -n "$duration" | grep "Cpu\|Mem"
            ;;

        *)
            echo "Unknown benchmark type. Available types: storage, graphics, system"
            ;;
    esac
}

###################
# Storage Monitor #
###################
check_storage() {
    echo "=== Storage Analysis ==="

    # List all block devices and their details
    echo "Block Devices Overview:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL

    # Show detailed partition information
    echo -e "\nPartition Details:"
    fdisk -l 2>/dev/null || parted -l 2>/dev/null

    # Check filesystem types and specific filesystem health
    echo -e "\nFilesystem Analysis:"
    # TODO: check if header should be included, or omision modified for proper formating (tail)
    for fs in $(df -T | tail -n +2 | awk '{print $1 " " $2}'); do
        device=$(echo $fs | cut -d' ' -f1)
        fstype=$(echo $fs | cut -d' ' -f2)
        echo -e "\n=== Analyzing $device ($fstype) ==="

        case $fstype in
            "btrfs")
                echo "BTRFS Filesystem Check:"
                btrfs device stats "$device" 2>/dev/null
                echo "BTRFS Balance Status:"
                btrfs balance status "$device" 2>/dev/null
                echo "BTRFS Subvolumes:"
                btrfs subvolume list "$device" 2>/dev/null
                echo "BTRFS Filesystem Usage:"
                btrfs filesystem usage "$device" 2>/dev/null
                ;;

            "zfs")
                echo "ZFS Pool Status:"
                zpool status $(zfs list -H -o name "$device" 2>/dev/null | head -1) 2>/dev/null
                echo "ZFS Dataset Properties:"
                zfs get all "$device" 2>/dev/null
                echo "ZFS Snapshot Space:"
                zfs list -t snapshot 2>/dev/null
                ;;

            "xfs")
                echo "XFS Filesystem Info:"
                xfs_info "$device" 2>/dev/null
                echo "XFS Filesystem Check:"
                xfs_repair -n "$device" 2>/dev/null
                ;;

            "ext4"|"ext3"|"ext2")
                echo "Ext Filesystem Check:"
                tune2fs -l "$device" 2>/dev/null
                echo "Filesystem Health:"
                e2fsck -n "$device" 2>/dev/null
                ;;
        esac
    done

    # Check disk space usage
    echo "Disk Space Usage:"
    df -h | grep -v "tmpfs"

    # Find largest directories in /
    echo -e "\nLargest Directories:"
    du -h / 2>/dev/null | sort -rh | head -n 10

    # Check inode usage
    echo -e "\nInode Usage:"
    df -i | grep -v "tmpfs"

    # Check for large files (>1GB)
    echo -e "\nFiles larger than 1GB:"
    find / -type f -size +1G -exec ls -lh {} \; 2>/dev/null

    # Check for deleted but open files
    echo -e "\nDeleted but open files:"
    lsof | grep "deleted"

    # Additional storage health checks
    echo -e "\nStorage Health Metrics:"

    # Check for disk fragmentation
    echo "Fragmentation Analysis:"
    for fs in $(df -h --output=source,fstype | tail -n +2); do
        device=$(echo $fs | awk '{print $1}')
        fstype=$(echo $fs | awk '{print $2}')

        case $fstype in
            "ext4"|"ext3"|"ext2")
                e4defrag -c "$device" 2>/dev/null || echo "e4defrag not available for $device"
                ;;
            "xfs")
                xfs_db -r -c "frag -f" "$device" 2>/dev/null || echo "xfs_db fragmentation check not available for $device"
                ;;
            "btrfs")
                btrfs filesystem defragment -v "$device" 2>/dev/null || echo "btrfs defragmentation not available for $device"
                ;;
            "jfs")
                jfs_fsck -f "$device" 2>/dev/null || echo "jfs_fsck not available for $device"
                ;;
            "ntfs")
                ntfsfragment "$device" 2>/dev/null || echo "ntfsfragment not available for $device"
                ;;
            "hfsplus")
                fsck.hfsplus -f "$device" 2>/dev/null || echo "fsck.hfsplus not available for $device"
                ;;
            "zfs")
                zpool iostat -v "$device" 2>/dev/null || echo "zpool iostat not available for $device"
                zfs get fragmentation "$device" 2>/dev/null || echo "zfs fragmentation check not available for $device"
                ;;
            *)
                echo "Unsupported file system type: $fstype for device $device"
                ;;
        esac
    done

    check_raid
}



###################
# Graphics Check  #
###################
check_graphics() {
    echo "=== Graphics Analysis ==="

    # Detect display server
    echo "Display Server Detection:"
    if pidof wayland 2>/dev/null; then
        echo "Wayland is running"

        # Check Wayland compositor
        echo -e "\nWayland Compositor:"
        echo $WAYLAND_COMPOSITOR
        ps aux | grep -i "wayland"

        # Check Wayland clients
        echo -e "\nWayland Clients:"
        ps aux | grep -i "wayland" | grep -v grep

        # Check Wayland logs
        echo -e "\nWayland Session Logs:"
        journalctl | grep -i "wayland" | tail -n 20
        # TODO: journalctl -u $WAYLAND_COMPOSITOR; cat ~/.config/$WAYLAND_COMPOSITOR
        # TODO: weston-debug; kwin --debug; gnome-shell --debug; mutter; sway; hyperland
    elif pidof X 2>/dev/null; then
        echo "X11 is running"

        # Check X server status
        echo -e "\nX Server Status:"
        ps aux | grep X

        # Check X logs
        echo -e "\nX Server Logs:"
        grep "EE" /var/log/Xorg.0.log 2>/dev/null
    else
        echo "Neither X11 nor Wayland detected"
    fi

    # GPU Information
    echo -e "\nGPU Hardware Information:"
    lspci -v | grep -A 8 -i 'vga\|3d\|2d'

    # Check for NVIDIA GPU
    # TODO: nvidia gpu without proprietary drivers will not work with this command
    if command -v nvidia-smi &> /dev/null; then
        echo -e "\nNVIDIA GPU Status:"
        nvidia-smi

        # Get NVIDIA memory usage
        echo -e "\nNVIDIA Memory Usage:"
        nvidia-smi --query-gpu=memory.used,memory.total --format=csv
    fi

    # Check for NON-NVIDIA GPU
    if [ -d "/sys/class/drm" ]; then
        echo -e "\nNON-NVIDIA GPU Status:"
        for gpu in /sys/class/drm/card[0-9]*/device/gpu_busy_percent; do
            if [ -f "$gpu" ]; then
                echo "GPU Usage: $(cat $gpu)%"
            fi
        done

        # Check AMD memory usage (if available)
        if [ -f "/sys/class/drm/card0/device/mem_info_vram_used" ]; then
            used=$(cat /sys/class/drm/card0/device/mem_info_vram_used)
            total=$(cat /sys/class/drm/card0/device/mem_info_vram_total)
            echo "VRAM Usage: $((used/1024/1024))MB / $((total/1024/1024))MB"
        fi
    fi

    # Check Intel GPU
    if command -v intel_gpu_top &> /dev/null; then
        echo -e "\nIntel GPU Status:"
        timeout 2 intel_gpu_top -J 2>/dev/null || echo "intel_gpu_top not available"
    fi

    # TODO: are the following in the script already?
        # - glxinfo | grep "Device"
        # - lspci -v | grep VGA

    # Check current resolution and refresh rate
    echo -e "\nDisplay Configuration:"
    if command -v wayland &> /dev/null; then
        wlr-randr 2>/dev/null || echo "wlr-randr not available"
    else
        xrandr 2>/dev/null || echo "xrandr not available"
    fi

    # Check driver and renderer information
    echo -e "\nGraphics Driver Info:"
    glxinfo 2>/dev/null | grep -E "OpenGL vendor|OpenGL renderer|OpenGL version" || echo "glxinfo not available"

    # Check for graphics-related kernel messages
    echo -e "\nRecent Graphics-Related Kernel Messages:"
    dmesg | grep -i -E "gpu|graphics|drm" | tail -n 10

    # Check for composition and rendering issues
    echo -e "\nCompositor Status:"
    ps aux | grep -i "compton\|picom\|mutter\|kwin\|compiz" | grep -v grep

    # Enhanced NVIDIA diagnostics
    if command -v nvidia-smi &> /dev/null; then
        echo -e "\nDetailed NVIDIA Diagnostics:"
        # Check GPU utilization history
        nvidia-smi --query-gpu=timestamp,utilization.gpu,utilization.memory --format=csv -l 1 -c 5

        # Check for ECC errors
        echo -e "\nNVIDIA ECC Error Check:"
        nvidia-smi --query-gpu=ecc.errors.corrected,ecc.errors.uncorrected --format=csv

        # Check thermal throttling
        echo -e "\nThermal Status:"
        nvidia-smi --query-gpu=temperature.gpu,temperature.maximum_threshold --format=csv

        # Check power state
        echo -e "\nPower State:"
        nvidia-smi --query-gpu=power.draw,power.limit --format=csv

        # Check compute mode and processes
        echo -e "\nCompute Processes:"
        nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv
    fi

    # Enhanced AMD diagnostics
    if command -v radeontop &> /dev/null; then
        echo -e "\nDetailed NON_NVIDIA Diagnostics:"
        timeout 5 radeontop -d- 2>/dev/null || echo "radeontop not available"

        # Check for DPM states
        if [ -f "/sys/class/drm/card0/device/power_dpm_state" ]; then
            echo -e "\nPower State:"
            cat /sys/class/drm/card0/device/power_dpm_state
        fi

        # Check current clock speeds
        if [ -f "/sys/class/drm/card0/device/pp_dpm_sclk" ]; then
            echo -e "\nGPU Clock Speeds:"
            cat /sys/class/drm/card0/device/pp_dpm_sclk
        fi
    fi

    # Graphics Problem Detection
    echo -e "\n=== Graphics Problem Detection ==="

    # Check for screen tearing
    echo "Screen Tearing Detection:"
    ps aux | grep -i "vsync" | grep -v grep
    if command -v vdpauinfo &> /dev/null; then
        echo "VDPAU Configuration:"
        vdpauinfo 2>/dev/null
    fi
    if command -v vainfo &> /dev/null; then
        echo "VA-API Configuration:"
        vainfo 2>/dev/null
    fi

    # Check for acceleration issues
    echo -e "\nAcceleration Status:"
    glxinfo | grep -i "direct rendering"

    # Check for compositor-specific issues
    echo -e "\nCompositor Diagnostics:"
    case $(ps aux | grep -Eo 'kwin|mutter|compiz|picom|compton|xfwm4|i3|awesome|openbox|fluxbox|dwm|sway' | head -1) in
            "kwin")
                qdbus org.kde.KWin /KWin supportInformation 2>/dev/null
                ;;
            "mutter")
                gsettings get org.gnome.mutter experimental-features 2>/dev/null
                ;;
            "picom"|"compton")
                grep -i "vsync\|glx\|backend" ~/.config/picom.conf 2>/dev/null ||
                grep -i "vsync\|glx\|backend" ~/.config/compton.conf 2>/dev/null
                ;;
            "xfwm4")
                xfconf-query -c xfwm4 -p /general/vblank_mode 2>/dev/null
                ;;
            "i3")
                grep -i "vsync\|compton" ~/.config/i3/config 2>/dev/null
                ;;
            "awesome")
                grep -i "vsync\|compton" ~/.config/awesome/rc.lua 2>/dev/null
                ;;
            "openbox")
                grep -i "vsync\|compositing" ~/.config/openbox/rc.xml 2>/dev/null
                ;;
            "fluxbox")
                grep -i "vsync\|overlay" ~/.config/fluxbox/overlay 2>/dev/null
                ;;
            "dwm")
                grep -i "vsync\|xinerama" ~/.config/dwm/config.h 2>/dev/null
                ;;
            "sway")
                sway --version 2>/dev/null
                grep -i "backend\|render" ~/.config/sway/config 2>/dev/null
                ;;
        esac

    # Check for driver conflicts
    echo -e "\nDriver Conflict Check:"
    lsmod | grep -E 'nvidia|nouveau|radeon|amdgpu|i915'

    # Check for known problematic configurations
    echo -e "\nConfiguration Issues:"
    # Check for hybrid graphics
    if ls /sys/class/drm/card*/ 2>/dev/null | grep -q "prime"; then
        echo "Hybrid Graphics detected - checking configuration:"
        grep -i "prime" /var/log/Xorg.0.log 2>/dev/null
    fi

    # Monitor refresh rate verification
    echo -e "\nRefresh Rate Verification:"
    if pidof wayland &>/dev/null; then
        wlr-randr 2>/dev/null || echo "wlr-randr not available"
    else
        xrandr --verbose | grep -A 1 "connected"
    fi

    # Buffer swap checking
    echo -e "\nBuffer Swap Analysis:"
    glxinfo 2>/dev/null | grep -i "swap"
}

###################
# Network Monitor #
###################
check_network() {
    echo "=== Network Analysis ==="

    # Check network interfaces
    echo "Network Interfaces:"
    ip a

    # Check routing
    echo -e "\nRouting Table:"
    ip route

    # Check DNS resolution
    echo -e "\nDNS Resolution Test:"
    ping -c 3 google.com 2>/dev/null || echo "DNS resolution failed"

    # Check active connections
    echo -e "\nActive Connections:"
    ss -tuln

    # Check network usage
    echo -e "\nCurrent Network Usage:"
    iftop -t -s 5 2>/dev/null || echo "iftop not available"

    # Check recent connection attempts
    echo -e "\nRecent Connection Attempts:"
    grep "connect" /var/log/syslog | tail -n 10
}

###################
# System Monitor  #
###################
check_system() {
    echo "=== System Analysis ==="

    # Check CPU usage and load
    echo "CPU Usage and Load:"
    top -b -n 1 | head -n 12

    # Check memory usage
    echo -e "\nMemory Usage:"
    free -h

    # Check for high CPU processes
    echo -e "\nTop CPU Consumers:"
    ps aux --sort=-%cpu | head -n 5

    # Check for memory leaks
    echo -e "\nPossible Memory Leaks:"
    ps aux --sort=-%mem | head -n 5

    # Check system logs for errors
    echo -e "\nRecent System Errors:"
    journalctl -p err..emerg --since "1 hour ago" 2>/dev/null || grep "error\|failed" /var/log/syslog | tail -n 10
}

###################
# Log Analysis    #
###################
analyze_logs() {
    local log_type=$1
    local hours=${2:-1}

    echo "=== Log Analysis for past $hours hour(s) ==="

    case $log_type in
        "auth")
            echo "Authentication Failures:"
            grep "authentication failure" /var/log/auth.log | tail -n 20
            ;;
        "kernel")
            echo "Kernel Issues:"
            dmesg | grep -i "error\|fail\|warning"
            ;;
        "system")
            echo "System Issues:"
            journalctl -p err..emerg --since "$hours hour ago"
            ;;
        *)
            echo "Unknown log type. Available types: auth, kernel, system"
            ;;
    esac
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n=== System Monitoring and Troubleshooting ==="
        echo "1. Check Storage"
        echo "2. Check Graphics"
        echo "3. Check Network"
        echo "4. Check System"
        echo "5. Analyze Logs"
        echo "6. Run Storage Benchmark"
        echo "7. Run Graphics Benchmark"
        echo "8. Run System Benchmark"
        echo "9. Exit"

        read -p "Select an option (1-9): " choice

        case $choice in
            1) check_storage ;;
            2) check_graphics ;;
            3) check_network ;;
            4) check_system ;;
            5)
                read -p "Enter log type (auth/kernel/system): " log_type
                read -p "Enter hours to look back: " hours
                analyze_logs "$log_type" "$hours"
                ;;
            6)
                read -p "Enter benchmark duration in seconds (default 30): " duration
                run_benchmarks "storage" "${duration:-30}"
                ;;
            7)
                read -p "Enter benchmark duration in seconds (default 30): " duration
                run_benchmarks "graphics" "${duration:-30}"
                ;;
            8)
                read -p "Enter benchmark duration in seconds (default 30): " duration
                run_benchmarks "system" "${duration:-30}"
                ;;
            9) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Run menu if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi

# TODO: add colors to log and echo statements
# TODO: add logging and historical comparison capabilities
# TODO: do i need statements to consider running certain things durring certain tests? (example: run a web browser while scrolling durring vdpua tests?)
# TODO: add "command does not exist" statements if command -v fails
# TODO: add failure statements (example: compositor not found)
# TODO: add memtest86 Function
# TODO: add check for dependencies checks. offer to install dependencies or only show main menu options that you have dependencies for
