#!/system/bin/sh

# ============================================
# Power2Swipe - 长按电源键触发三指上划
# ============================================

log_msg() {
    echo "[Power2Swipe] $*"
    log -t Power2Swipe "$*" 2>/dev/null || true
}

log_msg "Power2Swipe starting..."

three_finger_swipe() {
    log_msg "Triggering three-finger swipe via ColorDirectService"
    CLASSPATH=/system/framework/am.jar /system/bin/app_process /system/bin com.android.commands.am.Am start-foreground-service -p "com.coloros.colordirectservice" --ei "triggerType" 12
    log_msg "Three-finger swipe triggered"
}

# ---------- 工具函数 ----------

cleanup() {
    kill $GETEVENT_PID 2>/dev/null
    rm -f /data/local/tmp/power2swipe_fifo /data/local/tmp/power2swipe_pressed
    log_msg "Power2Swipe stopped"
    exit 0
}

trap cleanup EXIT
trap '' TERM INT

# ---------- 主循环 ----------

FIFO=/data/local/tmp/power2swipe_fifo
rm -f "$FIFO"
mkfifo "$FIFO" || {
    log_msg "ERROR: failed to create fifo"
    exit 1
}

getevent 2>/dev/null | grep --line-buffered ": 0001 0074 " > "$FIFO" &
GETEVENT_PID=$!
sleep 0.3
if ! kill -0 $GETEVENT_PID 2>/dev/null; then
    log_msg "ERROR: getevent/grep pipeline failed"
    exit 1
fi

log_msg "Power2Swipe monitoring started"

PRESS_FLAG=/data/local/tmp/power2swipe_pressed

while read -r line; do
    value="${line##* }"
    case "$value" in
            "00000001")
                touch "$PRESS_FLAG"
                (
                    sleep 1
                    if [ -f "$PRESS_FLAG" ]; then
                        three_finger_swipe
                        rm -f "$PRESS_FLAG"
                    fi
                ) &
                ;;
            "00000000")
                rm -f "$PRESS_FLAG"
                ;;
    esac
done < "$FIFO"
