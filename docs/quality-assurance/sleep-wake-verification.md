# QA — sleep/wake 복구 + dedupe 수동 검증

> 단위 테스트로 커버 불가한 실기기 동작. `.app` 빌드 후 실제 Razer 디바이스로 확인.
> 빌드: `./build-app.sh debug` → `open ".build/Tiny Razer.app"` (Input Monitoring 권한 1회 부여 필요).

## A. sleep/wake 복구
- [ ] 디바이스 연결 후 메뉴바에 값(DPI/배터리 등) 정상 표시
- [ ] 잠자기(애플 메뉴 → 잠자기 또는 ⌃⇧⏏) 진입 후 깨우기
- [ ] 깨어난 직후 Console.app 에서 `com.hyunseokbyun.tinyrazer` 로그에 `System woke — rebuilding HID transport` 확인
- [ ] **wake 후 30초 안에** 디바이스가 다시 인식되고 메뉴바 값이 갱신됨 (이전: 미인식)
- [ ] 디스플레이만 sleep(클램쉘/화면만 꺼짐) 후 wake 에서도 정상
- [ ] wake 직후 DPI/폴링 변경 write 가 디바이스에 반영됨

## B. 수동 Retry (권한 카드)
- [ ] Input Monitoring 권한이 없는 상태에서 PermissionCard 노출
- [ ] 권한 부여 후 **Retry** 클릭 → 디바이스 인식 (이전: 첫 Retry 이후 무동작이었음)

## C. 동글+케이블 dedupe
> 무선 마우스(예: DeathAdder/Basilisk V3 Pro)를 동글로 연결한 뒤 USB-C 케이블도 함께 연결.
- [ ] 동글만 연결 시: 메뉴에 1개(무선) 표시
- [ ] 케이블 추가 연결 시: 메뉴에 여전히 **1개**(유선으로 대체), 중복 없음. 로그 `Wired … replaces wireless …`
- [ ] 케이블만 분리 시: 무선 항목이 다시 resurface(로그 `Resurfacing …`)
- [ ] 서로 다른 디바이스 2개(예: 마우스 + 키보드)는 각각 별도 표시(over-merge 없음)

## 기대 결과 요약
- wake 후 자동 재인식, Retry 정상 동작, 동글+케이블은 항상 1개(유선 우선).
