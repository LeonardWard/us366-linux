# us366-linux

TASCAM US-366 USB 오디오 인터페이스를 리눅스에서 쓰기 위한 자동화 도구.
전용 커널 드라이버 없이, 기기에 내장된 **USB Audio Class 2.0 모드**를 활성화해
커널 기본 드라이버(`snd-usb-audio`)로 동작하게 한다.

## 배경

US-366(TEAC `0644:8041`)은 공식 리눅스 드라이버가 없는 기기다. 다만 두 가지
사실을 조합하면 기본 드라이버로 완전히 동작시킬 수 있다.

1. **기기에는 UAC 2.0 모드가 내장되어 있다.** USB 설정값(config)이 2개 있고,
   2번 설정(기본값 아님)이 표준 USB Audio Class 인터페이스를 노출한다.
   기본값인 1번 설정은 Windows/Mac 전용 벤더 프로토콜이다.

2. **기본값 모드는 커널 기본 드라이버가 자동으로 잡지 못한다.** 기기
   디스크립터의 `bDeviceClass`가 `0xFF`(Vendor Specific)라서, 커널의
   `usb_match_one_id()` 규칙상 vendor/product를 명시하지 않은 매칭 규칙은
   무시된다. 즉 오디오 인터페이스가 표준 클래스여도 매칭에서 제외된다.

따라서 ① 설정값을 2로 전환하고, ② `0644:8041`을 명시하는 동적 매칭 규칙
(`new_id`)을 추가하면 드라이버가 바인딩된다.

동작 확인된 스펙:

- 출력 4채널 / 입력 6채널
- 24bit, 최대 192kHz (44.1k~192k)
- 비동기 아이소크로노스 전송

## 사용법

요구 조건: 리눅스(커널 `snd-usb-audio` 포함 — 일반 배포판 기본), `udev`, sudo

```bash
# 즉시 활성화 (연결된 US-366에 바로 적용)
./us366-setup.sh

# USB 꽂기만으로 자동 활성화되게 설치 (권장)
./us366-setup.sh install

# 설치 제거
./us366-setup.sh uninstall
```

`install`은 udev 규칙(`/etc/udev/rules.d/99-tascam-us366.rules`)을 설치한다.
이후에는 재부팅, 재연결 모두 자동으로 인식된다.

설치 후 GNOME(또는 사용 중인 데스크톱)의 사운드 설정에서 출력/입력 장치로
"US-366"을 선택하면 된다.

## 동작 원리

스크립트(및 udev 규칙)가 하는 일은 세 가지뿐이다.

```bash
# 1. UAC 2.0 모드(config 2)로 전환
echo 2 > /sys/bus/usb/devices/<경로>/bConfigurationValue

# 2. 커널 기본 드라이버 로드
modprobe snd-usb-audio

# 3. vendor 명시 매칭 규칙 추가 (커널이 즉시 재탐색)
echo "0644 8041" > /sys/bus/usb/drivers/snd-usb-audio/new_id
```

1번을 먼저 하는 이유: 설정 1 상태에서 3번을 실행하면 벤더 클래스 인터페이스에
대한 무의미한 프로브가 먼저 일어나기 때문이다.

## 제한 사항

- US-366의 DSP 믹서/이펙터(Windows 전용 드라이버 기능)는 사용할 수 없다.
  UAC 모드의 기본 신호 경로(입력 → USB / USB → 출력)만 동작한다.
- ALSA 믹서 컨트롤이 없다(`amixer scontrols` 비어 있음). 볼륨은 재생
  애플리케이션/데스크톱과 기기 물리 노브(PHONES, 입력 게인)로 조절한다.
- 벤더 전용 인터페이스(패널 컨트롤 등)에 대한 `probe failed -22` 로그가
  남지만 무해하다. 오디오 인터페이스 바인딩에는 영향이 없다.

## 확인 환경

- Ubuntu (커널 6.17.0), US-366 펌웨어 bcdDevice 2.00

## 기타

- TASCAM US-144MKII는 별개다. 전용 드라이버(`us144mkii`)가 Linux 커널
  6.18부터 포함되어 있어 이 스크립트는 필요 없다.
- US-322(`0644:8040`)도 같은 방식이 통할 가능성이 있으나 미검증.
