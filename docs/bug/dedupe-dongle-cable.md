# 버그 — 동글+케이블 dedupe 가 실질적으로 동작 안 함

## 대상 파일
- `Sources/RazerKit/Catalog/DeviceDescriptor.swift` (`modelKey` 신규)
- `Sources/TinyRazer/Core/DeviceManager.swift` (`handle(.connected)`, `resurfaceSuppressedDevices()`)
- `Tests/RazerKitTests/DeviceCatalogTests.swift` (테스트 2개 추가)

## 증상
README가 광고하는 "동글과 USB 케이블로 동시에 연결된 디바이스 자동 dedupe(유선 우선)"가 작동하지 않는다. 같은 마우스가 메뉴에 **두 번** 나타날 수 있다.

## 근본 원인
`DeviceManager`의 Layer 2 dedupe 가 `descriptor.shortName` **동등 비교**로 같은 디바이스를 판정했다.
```swift
$0.device.descriptor.shortName == device.descriptor.shortName && ...
```
그러나 카탈로그(openrazer 생성)는 같은 물리 모델의 유선/무선 leg 에 **서로 다른 shortName**을 부여한다.
- `"DeathAdder V3 Pro Wired"` (0x00B6)
- `"DeathAdder V3 Pro Wireless"` (0x00B7)

두 문자열이 절대 같지 않으므로 predicate 가 **단 한 번도 발화하지 않는다**. 주석이 인용한 바로 그 DeathAdder V3 Pro 에서조차 유선이 무선을 evict 하지 못해, dedupe 가 dead 였다.

## 해결
1. `DeviceDescriptor.modelKey` 추가 — `shortName`의 **후행 연결성 토큰**(`Wired`/`Wireless`/`Receiver`/`Dongle`/`(Alt)`)을 단어 경계 기준으로 제거한 정규화 키. 예: `"DeathAdder V3 Pro Wired"`, `"… Wireless"`, `"… Wired (Alt)"` → 모두 `"deathadder v3 pro"`. (`Mobile` 등 제품명 일부는 토큰 집합에 없어 보존)
2. dedupe 판정을 `modelKey + category + isWireless 가 서로 다름`으로 변경 — **유선+무선 쌍**만 collapse 하고 유선 leg 를 선호. 같은 wiredness 끼리는 collapse 하지 않아(=distinct 보존) over-merge 위험을 최소화.
3. `resurfaceSuppressedDevices()`도 동일 기준으로 — 무선 leg 는 유선 counterpart 가 추적 중일 때만 억제, 유선이 빠지면 resurface.

## 트레이드오프 (적용 한계)
- 문자열 정규화 기반이라, 같은 base 이름의 **별개 제품**(예: "Lancehead" 유선 전용 vs "Lancehead Wireless")을 사용자가 **동시에** 연결하면 over-merge 가능. 실사용 빈도 매우 낮고, README 의도(유선 우선 collapse)와 합치하므로 수용.
- 더 견고한 근본책은 카탈로그(`gen-catalog.ts`)가 한 모델의 PID들을 단일 descriptor(`productIDs: Set`)로 묶는 것 — 255 엔트리 재생성이 필요한 큰 변경이라 이번 범위 밖.

## 검증
- 신규 테스트: `modelKey collapses wired/wireless/(Alt) variants of one model`(0x00B6/0x00C2/0x00B7 동일 키), `modelKey keeps distinct models distinct`(V3 Pro ≠ V2 Pro).
- `swift test` 51개 통과.
