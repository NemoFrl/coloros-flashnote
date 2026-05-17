#!/system/bin/sh

# ============================================
# FlashNote - 长按电源键触发一键闪记
# ============================================

log_msg() {
    echo "[FlashNote] $*"
    log -t FlashNote "$*" 2>/dev/null || true
}

log_msg "FlashNote starting..."

trigger_flash_note() {
    log_msg "Triggering flash note via ColorDirectService"
    CLASSPATH=/system/framework/am.jar /system/bin/app_process /system/bin com.android.commands.am.Am start-foreground-service -p "com.coloros.colordirectservice" --ei "triggerType" 12
    log_msg "Flash note triggered"
}

# ---------- 工具函数 ----------

cleanup() {
    kill $GETEVENT_PID 2>/dev/null
    rm -f /data/local/tmp/flashnote_fifo /data/local/tmp/flashnote_pressed
    log_msg "FlashNote stopped"
    exit 0
}

trap cleanup EXIT
trap '' TERM INT

# ---------- 主循环 ----------

FIFO=/data/local/tmp/flashnote_fifo
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

log_msg "FlashNote monitoring started"

PRESS_FLAG=/data/local/tmp/flashnote_pressed

while read -r line; do
    value="${line##* }"
    case "$value" in
            "00000001")
                touch "$PRESS_FLAG"
                (
                    sleep 1
                    if [ -f "$PRESS_FLAG" ]; then
                        trigger_flash_note
                        rm -f "$PRESS_FLAG"
                    fi
                ) &
                ;;
            "00000000")
                rm -f "$PRESS_FLAG"
                ;;
    esac
done < "$FIFO"
