#!/system/bin/sh

# ============================================
# Power2Swipe - 长按电源键触发三指上划
# ============================================

LONG_PRESS_MS=800

log_msg() {
    echo "[Power2Swipe] $*"
    log -t Power2Swipe "$*" 2>/dev/null || true
}

log_msg "Power2Swipe starting..."

# ---------- 查找触摸设备 ----------

find_touch_device() {
    local best=""
    local fallback=""
    for d in /dev/input/event*; do
        local props
        props=$(getevent -lp "$d" 2>/dev/null)
        if echo "$props" | grep -q "ABS_MT_POSITION_X"; then
            [ -z "$fallback" ] && fallback="$d"
            if echo "$props" | grep -q "BTN_TOUCH"; then
                best="$d"
            fi
        fi
    done
    echo "${best:-$fallback}"
}

TOUCH_DEV=$(find_touch_device)
if [ -z "$TOUCH_DEV" ]; then
    log_msg "ERROR: no touch device found"
    exit 1
fi
log_msg "Touch device: $TOUCH_DEV"

# ---------- 获取触摸屏原始分辨率 ----------

TOUCH_X_MAX=$(getevent -lp "$TOUCH_DEV" 2>/dev/null | grep "ABS_MT_POSITION_X" | grep -oE "max [0-9]+" | head -1 | cut -d' ' -f2)
TOUCH_Y_MAX=$(getevent -lp "$TOUCH_DEV" 2>/dev/null | grep "ABS_MT_POSITION_Y" | grep -oE "max [0-9]+" | head -1 | cut -d' ' -f2)

if [ -z "$TOUCH_X_MAX" ] || [ -z "$TOUCH_Y_MAX" ]; then
    log_msg "WARNING: failed to get touch resolution, using defaults"
    TOUCH_X_MAX=16383
    TOUCH_Y_MAX=65535
fi
log_msg "Touch range: X 0-$TOUCH_X_MAX  Y 0-$TOUCH_Y_MAX"

# ---------- 获取屏幕像素分辨率 ----------

SCREEN_SIZE=$(wm size 2>/dev/null | grep -oE "[0-9]+x[0-9]+" | head -1)
if [ -z "$SCREEN_SIZE" ]; then
    SCREEN_SIZE="1080x2400"
fi
SCREEN_W=${SCREEN_SIZE%x*}
SCREEN_H=${SCREEN_SIZE#*x}
log_msg "Screen: ${SCREEN_W}x${SCREEN_H}"

# ---------- 转像素坐标为触摸原始坐标 ----------

px_to_raw_x() {
    echo $(( $1 * TOUCH_X_MAX / SCREEN_W ))
}

px_to_raw_y() {
    echo $(( $1 * TOUCH_Y_MAX / SCREEN_H ))
}

# ---------- 三指上划 (sendevent 协议 B) ----------

three_finger_swipe() {
    local dev=$TOUCH_DEV

    local px_x1=$((SCREEN_W * 15 / 100))
    local px_x2=$((SCREEN_W * 50 / 100))
    local px_x3=$((SCREEN_W * 85 / 100))
    local px_y_start=$((SCREEN_H * 78 / 100))
    local px_y_end=$((SCREEN_H * 15 / 100))

    local rx1=$(px_to_raw_x $px_x1)
    local rx2=$(px_to_raw_x $px_x2)
    local rx3=$(px_to_raw_x $px_x3)
    local ry_start=$(px_to_raw_y $px_y_start)
    local ry_end=$(px_to_raw_y $px_y_end)
    local steps=8
    local dy=$(( (ry_start - ry_end) / steps ))

    log_msg "Injecting three-finger swipe (rx1=$rx1 rx2=$rx2 rx3=$rx3 ry=$ry_start->$ry_end)"

    sendevent "$dev" 3 57 16
    sendevent "$dev" 1 330 1
    sendevent "$dev" 1 325 1
    sendevent "$dev" 3 49 8
    sendevent "$dev" 3 58 7
    sendevent "$dev" 3 53 $rx1
    sendevent "$dev" 3 54 $ry_start

    sendevent "$dev" 3 47 1
    sendevent "$dev" 3 57 17
    sendevent "$dev" 3 49 9
    sendevent "$dev" 3 58 5
    sendevent "$dev" 3 53 $rx2
    sendevent "$dev" 3 54 $ry_start
    sendevent "$dev" 0 0 0

    sendevent "$dev" 3 47 2
    sendevent "$dev" 3 57 18
    sendevent "$dev" 3 48 12
    sendevent "$dev" 3 49 12
    sendevent "$dev" 3 58 8
    sendevent "$dev" 3 53 $rx3
    sendevent "$dev" 3 54 $ry_start
    sendevent "$dev" 0 0 0

    sleep 0.015

    # === 上划 ===
    for i in 1 2 3 4 5 6 7 8; do
        local y=$(( ry_start - dy * i ))
        sendevent "$dev" 3 47 0
        sendevent "$dev" 3 53 $rx1
        sendevent "$dev" 3 54 $y
        sendevent "$dev" 3 47 1
        sendevent "$dev" 3 53 $rx2
        sendevent "$dev" 3 54 $y
        sendevent "$dev" 3 47 2
        sendevent "$dev" 3 53 $rx3
        sendevent "$dev" 3 54 $y
        sendevent "$dev" 0 0 0
        sleep 0.003
    done

    # === 释放三指 ===
    sendevent "$dev" 3 47 2         # Slot 2
    sendevent "$dev" 3 57 -1        # TRACKING_ID = -1
    sendevent "$dev" 0 0 0          # SYN_REPORT

    sendevent "$dev" 3 47 0         # Slot 0
    sendevent "$dev" 3 57 -1        # TRACKING_ID = -1
    sendevent "$dev" 1 330 0        # BTN_TOUCH UP
    sendevent "$dev" 1 325 0        # BTN_TOOL_FINGER UP
    sendevent "$dev" 0 0 0          # SYN_REPORT

    sendevent "$dev" 3 47 1         # Slot 1
    sendevent "$dev" 3 57 -1        # TRACKING_ID = -1
    sendevent "$dev" 0 0 0          # SYN_REPORT

    log_msg "Three-finger swipe done"
}

# ---------- 工具函数 ----------

current_ms() {
    echo $(date +%s%3N 2>/dev/null || echo $(($(date +%s) * 1000)))
}

cleanup() {
    rm -f /data/local/tmp/power2swipe_fifo
    log_msg "Power2Swipe stopped"
    exit 0
}

trap cleanup EXIT TERM INT

# ---------- 主循环 ----------

FIFO=/data/local/tmp/power2swipe_fifo
rm -f "$FIFO"
mkfifo "$FIFO" || {
    log_msg "ERROR: failed to create fifo"
    exit 1
}

getevent 2>/dev/null | grep --line-buffered ": 0001 0074 " > "$FIFO" &
GETEVENT_PID=$!
sleep 0.5

if ! kill -0 $GETEVENT_PID 2>/dev/null; then
    log_msg "ERROR: getevent/grep pipeline failed"
    exit 1
fi

log_msg "Power2Swipe monitoring started (PID: $$)"

PRESS_TIME=0
PRESSED=false

while read -r line; do
    value="${line##* }"
    case "$value" in
        "00000001")
            if ! $PRESSED; then
                PRESS_TIME=$(current_ms)
                PRESSED=true
            fi
            ;;
        "00000000")
            if $PRESSED; then
                NOW=$(current_ms)
                ELAPSED=$(( NOW - PRESS_TIME ))
                log_msg "Power key UP after ${ELAPSED}ms"
                if [ "$ELAPSED" -ge "$LONG_PRESS_MS" ]; then
                    three_finger_swipe
                fi
            fi
            PRESSED=false
            ;;
    esac
done < "$FIFO"
