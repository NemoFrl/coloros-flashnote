#!/system/bin/sh

MODDIR=${0%/*}

# Wait for system to finish booting
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Start monitoring in background
nohup $MODDIR/power_monitor.sh > /dev/null 2>&1 &
