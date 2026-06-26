# 버그 — 잠자기(sleep) 후 깨어나면 디바이스 미인식

## 대상 파일
- `Sources/RazerKit/Transport/HIDTransport.swift` (`start()` / `stop()`, `manager`)
- `Sources/TinyRazer/Core/DeviceManager.swift` (`start()` / `stop()` / `restart()` / wake 옵저버)

## 증상
Mac이 잠자기에 들어갔다가 깨어나면 Tiny Razer가 Razer 디바이스를 더 이상 인식하지 못한다. 메뉴바 값이 멈추고, 메뉴의 **Retry** 를 눌러도 복구되지 않는다.

## 근본 원인 (공식 SDK 헤더로 확정)
두 가지 독립적 원인이 겹쳐 있었다.

1. **`IOHIDManagerCancel`은 terminal(되돌릴 수 없음)이다.**
   - dispatch-queue API(`IOHIDManagerSetDispatchQueue` + `IOHIDManagerActivate` + `IOHIDManagerCancel`)는 GCD dispatch source 를 모델로 한다.
   - `IOHIDManager.h`: *"An activated manager must be cancelled via IOHIDManagerCancel. … Calling IOHIDManagerActivate on an active IOHIDManager has no effect."* / *"IOHIDManagerSetDispatchQueue should only be made once."* / GCD 문서: *"Canceling a dispatch source … cannot be undone."*
   - 기존 코드는 `init()`에서 manager 를 **한 번** 만들고, `stop()`이 `IOHIDManagerCancel(manager)` 한 뒤 `start()`가 **같은 인스턴스**에 `IOHIDManagerActivate(manager)`를 재호출했다. → 첫 재시작 이후 manager 는 죽은 객체라 매칭/제거 콜백이 전혀 오지 않는다. (기존 "Retry" 버튼도 사실상 무동작이었다.)

2. **sleep/wake 전원 전이를 전혀 모니터링하지 않았다.**
   - USB HID 디바이스는 wake 시 **재열거(re-enumerate)** 되어 sleep 이전의 `IOHIDDeviceRef`가 stale 해진다.
   - 앱이 wake 신호를 구독하지 않으므로 transport 를 재구축할 계기가 없었다.

## 해결
1. **start 마다 새 IOHIDManager 를 생성.** `manager`를 `let` → `var manager: IOHIDManager?`로 바꾸고, 생성을 `init()`에서 `start()`로 이동. `stop()`은 Cancel 후 `manager = nil`. → Cancel 이후 재사용하지 않고 매 재시작마다 `IOHIDManagerCreate`로 새로 만든다(Apple 권장 시퀀스).
2. **wake 시 full restart.** `DeviceManager`가 `NSWorkspace.didWakeNotification`(UI 앱의 표준 wake 신호)을 구독해 `restart()`(stop→start)를 호출. start 가 새 manager 를 만들므로 모든 디바이스가 재매칭된다.
3. `restart()` 공개 메서드 추가(수동 Retry/wake 공용). 성공 재시작 시 `startupError = nil`로 stale 에러 정리.

## 검증
- `swift build` / `swift test`(51개) / `lint-swift-compat.sh` 통과.
- 실기기 sleep/wake 수동 검증은 단위 테스트로 불가 → `docs/quality-assurance/sleep-wake-verification.md` 체크리스트.

## 참고 (best practice 출처)
- 로컬 SDK 헤더 `IOKit.framework/Headers/hid/IOHIDManager.h`, `IOHIDDevice.h`, `IOMessage.h`(`kIOMessageSystemHasPoweredOn`)
- Apple GCD Concurrency Guide, `dispatch_source_cancel`, `NSWorkspace.didWakeNotification`, `IORegisterForSystemPower`
- Apple Forums thread 124444(매니저 레벨 removal 콜백이 신뢰 가능), Chromium `device/hid/hid_service_mac.cc`(매니저 1개 생성, cancel 후 재사용 안 함)
