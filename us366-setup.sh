#!/usr/bin/env bash
# TASCAM US-366 (TEAC 0644:8041) 리눅스 오디오 활성화 도구
#
# US-366은 기본으로 벤더 전용 USB 모드(config 1, bDeviceClass=0xFF)로 동작해
# snd-usb-audio가 자동으로 인식하지 못한다. 기기에 내장된 UAC 2.0 모드(config 2)로
# 전환하고 0644:8041 동적 매칭 규칙(new_id)을 추가하면 커널 기본 드라이버로
# 출력 4ch / 입력 6ch, 최대 24bit/192kHz까지 사용할 수 있다.
#
# 사용법:
#   ./us366-setup.sh           지금 연결된 US-366 즉시 활성화
#   ./us366-setup.sh install   USB 연결 시 자동 활성화되게 udev 규칙 설치
#   ./us366-setup.sh uninstall udev 규칙 제거

set -euo pipefail

VID="0644"
PID="8041"
DRIVER="snd-usb-audio"
NEW_ID_FILE="/sys/bus/usb/drivers/$DRIVER/new_id"
RULE_FILE="/etc/udev/rules.d/99-tascam-us366.rules"

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

find_us366() {
    local dev
    for dev in /sys/bus/usb/devices/*; do
        if [[ -f "$dev/idVendor" ]] \
            && [[ "$(cat "$dev/idVendor")" == "$VID" ]] \
            && [[ "$(cat "$dev/idProduct")" == "$PID" ]]; then
            echo "$dev"
        fi
    done
}

activate() {
    local dev found=0
    while IFS= read -r dev; do
        found=1
        if [[ "$(cat "$dev/bConfigurationValue")" != "2" ]]; then
            echo "UAC 모드(config 2)로 전환: $(cat "$dev/product") ($dev)"
            echo 2 > "$dev/bConfigurationValue"
        else
            echo "이미 UAC 모드(config 2)입니다: $dev"
        fi
    done < <(find_us366)

    if [[ $found -eq 0 ]]; then
        echo "US-366을 찾을 수 없습니다. USB로 연결한 후 다시 실행해 주세요." >&2
        exit 1
    fi

    modprobe "$DRIVER"

    if ! grep -qs "^$VID $PID" "$NEW_ID_FILE"; then
        echo "$VID $PID" > "$NEW_ID_FILE"
        echo "드라이버 매칭 규칙 추가: $VID:$PID"
    fi

    sleep 1
    if grep -qi "US-366" /proc/asound/cards; then
        echo "성공: ALSA 사운드 카드가 등록됐습니다."
        grep -A1 -i "US-366" /proc/asound/cards | sed 's/^/  /'
    else
        echo "경고: 카드가 아직 보이지 않습니다. dmesg를 확인해 보세요." >&2
        exit 1
    fi
}

install_rule() {
    cat > "$RULE_FILE" <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0644", ATTR{idProduct}=="8041", ATTR{bConfigurationValue}="2", RUN+="/usr/sbin/modprobe snd-usb-audio", RUN+="/bin/sh -c 'echo 0644 8041 > /sys/bus/usb/drivers/snd-usb-audio/new_id 2>/dev/null || true'"
EOF
    udevadm control --reload
    echo "udev 규칙 설치 완료: $RULE_FILE"
    echo "이제 USB를 꽂으면 자동으로 활성화됩니다."
}

uninstall_rule() {
    rm -f "$RULE_FILE"
    udevadm control --reload
    echo "udev 규칙 제거 완료: $RULE_FILE"
}

case "${1:-}" in
    ""|activate) activate ;;
    install)     install_rule ;;
    uninstall)   uninstall_rule ;;
    *) echo "사용법: $0 [activate|install|uninstall]" >&2; exit 2 ;;
esac
