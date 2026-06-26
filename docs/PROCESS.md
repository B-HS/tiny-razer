# PROCESS — Tiny Razer 작업 상태

> 기준 문서: `~/.claude/CLAUDE.md` + `~/.claude/convention/*` (ai-process · common · comments · git · desktop)
> 이 프로젝트는 Swift(SPM, macOS 14+) 기반이므로 FE/BE/FSD 컨벤션은 비적용. ai-process · git · comments(주석)·minimal-diff 원칙은 적용.
> **기존 코드 스타일 준수**: 이 코드베이스는 Swift doc comment(`///`)와 설명 주석을 사용 중이므로, comments.md 의 "주석 금지"보다 §6.8(기존 스타일 유지·최소 변경)을 우선한다.

## 현재 작업 (2026-06-26)

- [x] 1. 프로젝트 완전 파악 — 13-에이전트 워크플로우로 9개 서브시스템 + 3개 흐름 분석 완료 → `docs/memory/architecture.md`
- [x] 2. 종합 문서 `docs/` 저장 — `docs/memory/architecture.md`
- [x] 3. 명백한 버그 수정
  - [x] 3a. 동글+케이블 dedupe dead 버그 — `DeviceDescriptor.modelKey` 정규화 + dedupe 를 modelKey+category+isWireless-차이 로 변경. 테스트 2개 추가. → `docs/bug/dedupe-dongle-cable.md`
  - [x] 3b. standard starlight dataSize — **오탐**. openrazer 원본 대조 결과 dataSize 0x01 이 정확(원본도 동일), starlight 3종 모두 이미 clamp 적용 중. 유일한 차이 reactive clamp 누락은 `EffectSpeed`∈{1..4}라 no-op. **수정 불필요.**
- [x] 4. sleep/wake 후 미인식 버그 (사용자 보고)
  - [x] 4a. 근본 원인 확정 — 공식 SDK 헤더로 확인: `IOHIDManagerCancel` terminal(동일 인스턴스 재Activate 무효) + sleep/wake 모니터링 부재. → `docs/bug/sleep-wake-not-recognized.md`
  - [x] 4b. 수정 — `HIDTransport` start 마다 새 `IOHIDManagerCreate` + `DeviceManager`가 `NSWorkspace.didWakeNotification` 구독 → `restart()`
- [x] 5. 빌드·테스트 검증 — `swift build` ✓ / `swift test` 51개 ✓ / `lint-swift-compat.sh` ✓
- [x] 6. 결과 분류 저장 — `docs/bug/*`, `docs/quality-assurance/sleep-wake-verification.md`, `docs/history/`
- [ ] 7. (대기) 실기기 sleep/wake·dedupe 수동 검증 — `docs/quality-assurance/sleep-wake-verification.md`
- [ ] 8. (대기) 커밋 — 사용자 요청 시. 논리 단위 분리 권장: ① fix(transport) sleep/wake, ② fix(catalog) dedupe

## 검증 방법
- `swift build` 성공
- `swift test` 통과(기존 49 + 신규)
- sleep/wake 는 실기기 수동 검증 필요(테스트 불가 영역) — `docs/quality-assurance` 에 체크리스트

## 미결정/주의
- dedupe 정규화는 문자열 기반이라 같은 base 의 별개 제품(예: "Lancehead" 유선 전용 vs "Lancehead Wireless")이 동시 연결 시 over-merge 가능 — 실사용 빈도 낮음, README 의도(유선 우선 collapse)와 합치. docs 에 트레이드오프 명시.
