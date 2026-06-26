# 2026-06-26 — 프로젝트 파악 + sleep/wake·dedupe 버그 수정

## 작업
1. **전체 파악**: 13-에이전트 워크플로우(9 서브시스템 정밀 분석 + 3 end-to-end 흐름 추적 + 종합) → `docs/memory/architecture.md`.
2. **버그 수정 2건** + **오탐 1건 정정**.

## 변경 파일
- `Sources/RazerKit/Transport/HIDTransport.swift` — `manager` 를 재생성 가능하게(`var ...?`), start 마다 `IOHIDManagerCreate`, stop 에서 nil.
- `Sources/TinyRazer/Core/DeviceManager.swift` — `NSWorkspace.didWakeNotification` 구독 + `restart()`; dedupe 를 `modelKey` 기반으로.
- `Sources/RazerKit/Catalog/DeviceDescriptor.swift` — `modelKey` 정규화 프로퍼티.
- `Tests/RazerKitTests/DeviceCatalogTests.swift` — modelKey 테스트 2개.

## 핵심 결론
- **sleep/wake 미인식** 근본 원인: `IOHIDManagerCancel` 은 terminal → 동일 인스턴스 재Activate 무효(기존 Retry 도 무동작). + wake 모니터링 부재. (공식 SDK 헤더 확인)
- **dedupe dead**: shortName 동등 비교가 wired/wireless 다른 이름이라 미발화. modelKey 정규화로 해결.
- **starlight dataSize 는 버그 아님**(오탐): openrazer 원본도 dataSize 0x01, Swift 포팅 충실. clamp 누락(reactive)은 enum 범위상 no-op.

## 검증
`swift build` ✓ · `swift test` 51개 ✓ · `lint-swift-compat.sh` ✓. 실기기 검증은 `docs/quality-assurance/sleep-wake-verification.md` 대기.

## 미커밋
사용자 요청 시 커밋. 논리 단위: ① fix(transport): sleep/wake 복구, ② fix(catalog): 동글+케이블 dedupe.
