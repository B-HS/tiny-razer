# Tiny Razer — 기술 이해 문서 (Definitive Understanding)

> 출처: 13-에이전트 워크플로우(9개 서브시스템 정밀 분석 + 3개 end-to-end 흐름 추적 + 종합). 2026-06-26 생성.
> 바이트 단위 프로토콜·command id·CRC 벡터·동시성 모델·빌드 파이프라인을 모두 보존한 단일 출처(SSOT).

## 1. 한 줄 정의 + 핵심 가치 제안

**Tiny Razer**는 Synapse·데몬·kext 없이 IOKit HID 위에서 직접 Razer 주변기기를 제어하는 네이티브 Swift macOS 메뉴바 앱입니다. (약 8,000줄 Swift, Swift 6 language mode, macOS 14+)

**왜 Synapse 대신인가**
- **무데몬·무커널**: 백그라운드 데몬도 커널 확장도 없습니다. `IOHIDDeviceSetReport`/`GetReport`로 90바이트 feature report만 주고받습니다.
- **경량 메뉴바 에이전트**: `LSUIElement=true`, `.accessory` activation policy. Dock 아이콘 없이 상태바 아이템 하나로 동작합니다.
- **권한 최소화**: 샌드박스 미사용·entitlement 0개. macOS TCC의 **Input Monitoring** 권한만 런타임에 요구하며, 그조차 첫 I/O 시점에 lazy하게 감지합니다.
- **오픈 소스 유래의 검증된 프로토콜**: 모든 와이어 상수·디바이스 카탈로그가 openrazer 드라이버(C) + 데몬(Python)에서 기계적으로 유도되어 손으로 만든 quirk가 없습니다.
- **255종 디바이스** 지원 카탈로그를 정적 데이터로 내장합니다.

## 2. 전체 아키텍처

두 개의 SPM 타깃, 의존 방향은 **단방향(TinyRazer → RazerKit)**.

```
TinyRazer (executable) — @MainActor, SwiftUI/AppKit
  App/      TinyRazerApp · AppDelegate · StatusBarController
  Core/     DeviceManager · DeviceState · FieldPreferences · LaunchAtLogin · Log
  Menu/     MenuBarView (NSPopover 패널)
  Settings/ SettingsScene · GeneralSettingsView · LightingPicker
  UI/       DesignTokens · WindowAccessor
        │  await (오직 transport 호출만 actor hop)
        ▼
RazerKit (library) — 순수 값 타입 + 단일 actor
  Protocol/  RazerReport · CRC · CommandID · TransactionID · ReportStatus · LEDTypes
  Transport/ HIDTransport(actor) · DeviceRegistry · HIDDeviceHandle · TransportError
  Commands/  MiscCommands · LEDCommandsStandard · LEDCommandsExtended
  Device/    RazerDevice (per-handle facade) · Features/Capability
  Catalog/   DeviceCatalog · DeviceDescriptor · Category · Generated/{Mouse,Keyboard,Headset,Mousepad,Accessory}Catalog
```

- **RazerKit는 SwiftUI/DeviceManager를 전혀 모릅니다.** UI는 IOKit을 직접 만지지 않습니다.
- 레이어 흐름: SwiftUI → `DeviceManager`(상태/오케스트레이션) → `RazerDevice`(facade) → `MiscCommands`/`LED*`(바이트 빌더) → `RazerReport`/`CRC`(와이어 포맷) → `HIDTransport`(IOKit).
- `IOHIDDevice` 포인터는 `HIDTransport`/`DeviceRegistry` 밖으로 절대 나가지 않습니다. 상위는 `HIDDeviceHandle`(Sendable 값 타입, `UInt64 id`)로만 하드웨어를 지칭. (`@preconcurrency import IOKit`)
- Package.swift: `swift-tools-version:6.0`, `.macOS(.v14)`, 외부 의존성 **0개**, 세 타깃 모두 `swiftLanguageMode(.v6)`.

## 3. 와이어 프로토콜 (90바이트 리포트, 바이트 단위)

`RazerReport`는 `[UInt8]`(크기 90) 백킹 `Sendable, Equatable` 구조체. 상수: `byteCount=90`, `argumentsOffset=8`, `argumentsCount=80`, `crcOffset=88`.

| 오프셋 | 필드 | 내용 |
|------|------|------|
| `[0]` | status | ReportStatus (응답 시 device가 채움) |
| `[1]` | transaction_id | device(상위 3bit) \| id(하위 5bit) |
| `[2..3]` | remaining_packets | **빅엔디언 u16** |
| `[4]` | protocol_type | 항상 `0x00` (zero-fill 의존) |
| `[5]` | data_size | ≤ 80 |
| `[6]` | command_class | |
| `[7]` | command_id | direction(bit7) \| id(bits6..0) |
| `[8..87]` | arguments | 80바이트 |
| `[88]` | crc | XOR of bytes `[2,88)` |
| `[89]` | reserved | `0x00` |

- **CRC**: `CRC.calculate` = bytes `[2,88)`(즉 2~87, 86바이트) XOR. **status·transaction_id 의도적 제외**. openrazer `razercommon.c:131-144` 포팅. 아웃바운드는 `finalized()`가 송신 직전 자동 계산. 수신 리포트는 CRC 검증 안 함.
- **CommandID**: `init(direction:id:) = (direction<<7) | (id & 0x7F)`. `Direction.set=0x00`(write), `.get=0x01`(read). 예: get+0x05 → 0x85.
- **TransactionID**: `((device & 0b111) << 5) | (id & 0b11111)`. `.zero=0x00`, `.standard=0xFF`. descriptor 기본값 0x1f.
- **ReportStatus**: `new=0x00, busy=0x01, successful=0x02, failure=0x03, timeout=0x04, notSupported=0x05`.
- **LEDZone**(비연속): `matrix=0x00, scrollWheel=0x01, battery=0x03, logo=0x04, backlight=0x05, macro=0x07, gameMode=0x08, rightSide=0x10, leftSide=0x11, charging=0x20`.
- **최상위 상수**: `vendorID=0x1532`, `reportLength=90`, `reportWValue=0x0300`(Feature 0x03<<8 | reportID 0x00).

## 4. Transport (IOKit HID, actor 동시성 모델)

세 동시성 도메인, 두 하드 경계:
1. **`actor HIDTransport`** — 모든 IOKit feature-report I/O 직렬화.
2. **`final class DeviceRegistry: @unchecked Sendable`** — `NSLock` 보호 비격리 테이블. IOKit C 콜백이 전용 디스패치 큐(`tiny-razer.hid-transport`, qos `.userInitiated`)에서 발생하므로 actor 밖.
3. **`AsyncStream<DeviceEvent>`** — 콜백 스레드 → continuation → `DeviceManager`(@MainActor)로 Sendable 이벤트 전달하는 유일한 다리.

**start()**: AsyncStream 설치(매칭 전) → vendorID 매칭 → 디스패치 큐 핀 → C 콜백 등록(context = `Unmanaged.passUnretained(registry)`) → **`IOHIDManagerActivate`만 호출, `IOHIDManagerOpen`은 일부러 생략**(Input Monitoring 없이도 매칭+feature I/O 동작). `ensureDeviceOpen`이 첫 feature op 시 `IOHIDDeviceOpen`(non-seize) lazy 호출.

**디스커버리·디듀프(Layer 1)**: `dedupeKey = serial ? "sn-{pid}-{serial}" : "loc-{pid}-{locationID}"`. `isVendorCollection = usagePage >= 0xFF00`. 첫 collection이 primary, 같은 key 이후 collection은 fallback. vendor collection 도착 시 promote(재방출 없음).

**send()**(write, fire-and-forget): `finalized()` → primary `setFeatureReport`, 실패 시 fallback 순회. **promote 안 함**. **request()**(read): candidates = primary + fallbacks. 각각 SetReport → `sleep 3ms`(`defaultResponseDelay`) → GetReport. `.successful` → `promotePrimary` 후 반환; `.new(0x00)` → 다음 candidate; 소진 시 `lastError ?? .timeout`.

**TransportError**: `transportNotStarted, deviceNotConnected, invalidResponseLength, ioKitError(Int32), reportStatus, timeout, notPermitted`. 권한 거부는 `.notPermitted`가 아니라 `ioKitError(0xE00002E2)`로 표면화, `isPermissionDenied`로 식별.

## 5. Commands (DPI/폴링/배터리/LED)

순수 무상태 빌더. 동시성 어노테이션 0개. openrazer `razerchromacommon.c` 포팅.

**MiscCommands** (store: `noStore=0x00, varStore=0x01`):

| 기능 | class | id | dataSize |
|------|------|----|---------|
| setDPI | 0x04 | set 0x05 | 0x07 (clamp 100..45000, BE) |
| getDPI | 0x04 | get 0x05 | |
| setPollingRate(classic) | 0x00 | 0x05 | 0x01 |
| setPollingRate2(hyper) | 0x00 | 0x40 | set 0x02/get 0x01 |
| getBatteryLevel | 0x07 | 0x80 | 0x02 (round arg1/255×100) |
| getChargingStatus | 0x07 | 0x84 | 0x02 (arg1!=0) |
| getFirmwareVersion | 0x00 | 0x81 | 0x02 ("v{a}.{b}") |
| getSerialNumber | 0x00 | 0x02 | 0x16(22) |
| DPI stages | 0x04 | 0x06 | 0x26(38), 최대 5×7B |
| idle timer | 0x07 | 0x03 | clamp 60..900s, BE |
| low-battery threshold | 0x07 | 0x01 | 0x01 (clamp 0x0C..0x3F) |

**Standard vs Extended LED 분기 (핵심)**:

| | Standard | Extended |
|---|---------|----------|
| class | **0x03** | **0x0F** |
| 효과 id | set **0x0A** | set **0x02** |
| 헤더 | arg0=effectID | arg0=store, arg1=zone, arg2=effectID |
| 밝기 | id 0x03 | id 0x04 |

같은 효과의 effectID가 family별로 다름. 카탈로그 실측: `.extendedEffects`는 **MouseCatalog 62회**, 그 외 0회 → **마우스만 extended(0x0F), 나머지 classic(0x03)**.

## 6. Device + Capability

`RazerDevice`(`Sendable, Identifiable, Equatable`, actor 어노테이션 없음): `handle` + `descriptor`, `id == handle.id`. `from(handle:)`는 vendor 가드 + `DeviceCatalog.descriptor(for:)`. `stamp(_:)`는 transactionID만 씀(CRC는 transport `finalized()`).

`LEDEffect`(11 케이스): off/static/spectrum/wave/reactive/breathing(Single·Dual·Random)/starlight(Single·Dual·Random).

`Capability`(18 케이스, String raw): dpi, dpiHyper, dpiStages, pollingRate, pollingRateHyper, battery, charging, idleTimer, lowBatteryThreshold, brightness, rgbStatic/Breathe/Spectrum/Wave/Reactive/Starlight, customFrame, extendedEffects. **코드 분기는 2개만**: `.extendedEffects`(LED class 선택), `.pollingRateHyper`(getPollingRate2 선택). 나머지는 `supports(_:)` 자문 플래그. **RazerDevice는 feature 메서드를 capability로 가드하지 않고 무조건 실행** — 게이팅은 UI 책임.

읽기/쓰기 폴링 비대칭: read는 `capabilities.contains(.pollingRateHyper)`, write는 `descriptor.hyperPollingRates.contains(rate)` 사용.

## 7. Catalog (255 디바이스)

완전 자동생성 정적 레지스트리. `DeviceDescriptor`: displayName, shortName, category, productIDs(Set<Int>), capabilities, maxDPI, hyperPollingRates, isWireless, transactionID(기본 0x1f). `DeviceCatalog.descriptor(for:)`는 lazy static map, O(1).

- **총 255**: Mouse **113** / Keyboard **110** / Headset **8** / Mousepad **8** / Accessory **16**.
- **각 descriptor는 정확히 PID 1개**. wired/wireless/(Alt) 변형마다 별도 단일-PID 엔트리(예: DeathAdder V3 Pro = 0x00B6/0x00C2/0x00B7/0x00C3 4개).
- transactionID 분포: `0xff×114`, `0x1f×88`, `0x3f×47`, `0x9f×6`(무선 키보드).
- hyperPollingRates: `.pollingRateHyper` 가진 15개만 풀셋. maxDPI: 마우스만(0~45000), 그 외 0.
- Capability 빈도(상위): rgbStatic 207, rgbSpectrum 192, rgbBreathe 182, customFrame 162, ... extendedEffects 62, pollingRateHyper 15. **`.dpiHyper`는 0회(dead)**.
- 모든 생성 파일 헤더: `AUTO-GENERATED by scripts/gen-catalog.ts ... Source: github.com/openrazer/openrazer @ master`.

## 8. TinyRazer 앱 (lifecycle, 오케스트레이션)

**부트스트랩**: `TinyRazerApp`(@main) → `@NSApplicationDelegateAdaptor`. 유일 Scene은 settings `Window`(MenuBarExtra 없음). `AppDelegate`(@MainActor): 3개 모델 즉시 생성 → `applicationDidFinishLaunching`(nonisolated)이 `Task{@MainActor}` → `.accessory` → `await deviceManager.start()` → StatusBarController. `applicationShouldTerminateAfterLastWindowClosed=false`.

**DeviceManager**(`@MainActor @Observable`): `start()`이 `transport.start()` 스트림을 observerTask로 소비. `handle(.connected)` → `RazerDevice.from(handle:)` → dedupe → DeviceState append → `refreshState` → `startPolling`(30초). `handle(.disconnected)` → 폴링 cancel + `resurfaceSuppressedDevices()`.

**동글+케이블 dedupe(Layer 2)**: 같은 `descriptor.shortName` + `category` 검색, 신규 wired가 기존 wireless를 evict. **⚠️ 버그: 카탈로그가 wired/wireless에 다른 shortName을 주므로 predicate 미발화 → 실질 dead** (수정 대상, `docs/bug/` 참조).

**StatusBarController**: NSStatusItem + NSPopover. Observation 미사용, **200ms 루프**로 라벨 재드로.

보조 모델: `DeviceState`(struct, LED 필드 없음 → setLEDEffect write-only), `FieldKind`(dpi/pollingRate/battery/charging), `FieldPreferences`(@Observable, UserDefaults `fieldPrefs.v1.`, `revision` bump으로 SwiftUI 갱신), `LaunchAtLogin`(SMAppService.mainApp), `Log`(3 os.Logger, subsystem `com.hyunseokbyun.tinyrazer`).

## 9. UI

3개 `@Observable` 클래스가 AppDelegate에서 1회 생성, `@Bindable` 주입.
- **MenuBarView**(300pt): field 토글, 라이브 값, dpiPresets `[400,800,1600,3200]`, PermissionCard(deep link + Retry=stop+start).
- **SettingsScene**(사이드바 220 + 디테일): DPI Slider/presets `[400,800,1600,3200,6400]`/custom XY(link 토글), polling, LightingPicker(write-only, read-back 없음), BrightnessSlider, IdleTimerRow, LowBatteryRow.
- **DesignTokens**(`DS`): Spacing/Radius/Palette, Card·BatteryRing·PresetChips. **WindowAccessor**: NSViewRepresentable, miniaturize/zoom 버튼만 숨김.
- **WRITE 흐름**: 모든 컨트롤 `Task { await manager.setXxx(...) }` fire-and-forget. setDPI/setBrightness는 낙관적 갱신, **setPollingRate·setLEDEffect는 상태 미갱신**(30초 폴링 전까지 미반영).

## 10. 핵심 End-to-End 흐름

**A. 연결→read→메뉴바**: 부트 → transport arming(Activate만) → IOKit 콜백(off-actor) → AsyncStream → @MainActor handle → `RazerDevice.from` → dedupe → refreshState(capability별 read, actor hop) → `devices[index]=state` → 30초 폴링. StatusBar 200ms 재드로.

**B. DPI 변경→write**: UI(slider/preset/custom) → `Task{ setDPI }` → MainActor 인덱스 → `device.writeDPI` → `MiscCommands.setDPI`(clamp) → stamp(txid) → actor hop `transport.send` → `finalized()`(CRC) → `ensureDeviceOpen` → `IOHIDDeviceSetReport(Feature,0x00,90)` → 실패 시 fallback.

**C. 런칭→권한→dedupe**: 권한은 첫 feature op `IOHIDDeviceOpen`이 TCC 거부 시 `0xE00002E2` → `noteError` → `needsInputMonitoringPermission=true` → PermissionCard. 캐던스: StatusBar 200ms, DeviceManager 30초, Set→Get 3ms. 연결/해제는 콜백 구동.

## 11. 테스트 커버리지

**swift-testing 100%**(XCTest 0). `RazerKitTests` 단일 타깃, **총 49 @Test / 8 @Suite / 6파일**: 90바이트 레이아웃, CRC 벡터, command 바이트 벡터(setDPI/polling/battery/charging), LED(classic 5+extended 3+misc 6), 카탈로그 무결성.

**테스트 안 됨**: TinyRazer 앱 타깃 전체(DeviceManager/UI), Transport 실 IOKit 경로, 통합/실기기 round-trip, 카탈로그 exact-count.

## 12. 빌드/CI/릴리스

- **build-app.sh**: codesign identity 5단 우선순위(`$CODESIGN_IDENTITY` → Developer ID → Apple Development → self-signed → ad-hoc), hardened runtime 서명. `.app` 번들 조립(BUNDLE_NAME에 공백, product는 공백 없음).
- **Entitlements**: 빈 `<dict/>` — 샌드박스·entitlement 0개. Input Monitoring은 TCC 런타임(Info.plist `NSInputMonitoringUsageDescription`).
- **Info.plist**: `LSUIElement=true`, `CFBundleIdentifier=com.hyunseokbyun.tinyrazer`, `LSMinimumSystemVersion=14.0`.
- **CI(ci.yml)**: macos-15, Xcode 16.2 하드코딩 → `lint-swift-compat.sh`(trailing comma 차단) → `swift build`/`swift test`.
- **Release(release.yml)**: main push마다 자동 patch 릴리스, semver 계산 → cert import → `build-app.sh release` → 버전 스탬프 재서명 → notarize(secret 있으면) → GitHub Release.
- **gen-catalog.ts**(Bun, 수동): openrazer @ master raw fetch·파싱 → Generated/*.swift. **커밋 미핀(BRANCH='master'), regen CI 게이트 없음 → drift 가능**.

## 13. 동시성/안전성 모델 (Swift 6 strict)

3개 격리 도메인: `@MainActor`(UI+상태), `actor HIDTransport`(IOKit I/O), `DeviceRegistry: @unchecked Sendable`(NSLock, 콜백 스레드). Protocol/Commands/Catalog는 동시성 프리미티브 0개(불변 Sendable 값 타입). `@preconcurrency import IOKit`로 비-Sendable IOKit 격리. DeviceManager는 `devices`를 MainActor에서만 mutate, 각 await 뒤 `firstIndex(id==)` 재탐색으로 중간 제거 방어.

## 14. 미구현/로드맵 + 리스크

**확인/잠재 버그**:
- ~~**Layer 2 dedupe dead**~~: **수정됨(2026-06-26)** — `DeviceDescriptor.modelKey` 정규화 + dedupe 키 변경. → `docs/bug/dedupe-dongle-cable.md`
- ~~**sleep/wake 후 미인식(사용자 보고)**~~: **수정됨(2026-06-26)** — `IOHIDManagerCancel`이 terminal이라 동일 인스턴스 재Activate 무효였음. start마다 새 `IOHIDManagerCreate` + `NSWorkspace.didWakeNotification` 구독. → `docs/bug/sleep-wake-not-recognized.md`
- ~~**standard starlight dataSize 의심**~~: **오탐(2026-06-26)** — openrazer 원본도 dataSize 0x01, Swift 포팅 충실. starlight 3종 모두 이미 clamp 적용. reactive clamp 누락만 남으나 `EffectSpeed`∈{1..4}라 no-op. **수정 불필요.**
- **startupError UI 무음**: transport 시작 실패 로깅만, View 미참조. (미해결 — 단 성공 재시작 시 startupError는 이제 초기화)
- **needsInputMonitoringPermission 미리셋**: 권한 부여 후 false 복원 경로 없음(수동 Retry만). (미해결)

**dead 코드**: `.dpiHyper`(카탈로그 0회), `.customFrame`(빌더 없음), `setLEDState`/`setLEDRGB`(호출자 없음), `DeviceCategory.eGPU/dock`, `TransportError.timeout/.notPermitted`, multi-PID `productIDs:Set`.

**UI 일관성**: LED write-only, setPollingRate/setLEDEffect 낙관적 갱신 없음, state.pollingRate 미하이라이트, Menu(3200) vs Settings(6400) preset 불일치.

**인프라**: main push마다 자동 릴리스, 릴리스 노트 "notarized" 오기 가능, 카탈로그 drift, `--deep` 서명(deprecated), Xcode 16.2 경로 하드코딩.

**로드맵**(README): per-key RGB(`customFrame`), ripple, 하드웨어 매크로, 온보드 프로필, game-mode, per-zone LED, set_dpi_xy_byte(`dpiHyper`).
