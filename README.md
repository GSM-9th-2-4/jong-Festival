# 종 페스티벌 미니게임 (할인 쿠폰)

Python + pygame-ce. 부스 노트북 한 대에서 키오스크로 실행.
대기 화면 → 게임 선택 → (확률표로 경품 추첨) → 게임이 결과대로 연출 → 쿠폰 화면.

확률: 꽝 50% / 대박(전액 면제) 2% / 500원 25% / 1,000원 15% / 2,000원 8% — `core/store.py` 의 `PRIZES`

## 실행
```
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python main.py            # 창 모드 (개발용)
FESTIVAL_PIN=4821 python main.py --kiosk   # 부스용: 전체화면, ESC로 못 끔
```

## 부스 운영 (스태프용)
| 키 | 동작 |
|---|---|
| F1 | 관리자 화면 (PIN 입력, 기본 `0000` — 꼭 `FESTIVAL_PIN` 으로 바꿔서 실행) |
| F2 | 당첨 화면에서 누르면 그 쿠폰을 바로 "사용 완료" 처리 |
| F11 | 전체화면 전환 |

관리자 화면: 경품별 나온 수/실제 확률/사용 완료 수, 쿠폰 코드 입력해서 사용 처리(중복 사용 차단),
F5 = `coupons.csv` 로 내보내기, F10 = 프로그램 종료.

- 모든 기록은 `festival.db` 에 저장됨 (꽝 포함). 축제 시작 전에 이 파일을 지우면 초기화
- 경품 수량 제한: `PRIZES` 에서 `Prize("대박! 전액 면제", 2, cap=3)` 처럼 `cap` 을 주면 그 수량 이후로는 꽝 처리
- 게임 도중 ESC로 나가도 이미 뽑힌 결과는 다음 판에 그대로 적용됨 (다시 뽑기 불가)

## 게임 추가하는 법 (충돌 안 나는 규칙)
1. `git switch -c game/<내게임>` — main 에 직접 push 금지
2. `games/_template.py` 복사 → `games/<내게임>.py`
3. **내 파일(`games/<내게임>.py`, `games/assets/<내게임>/`)만 수정.** `main.py`, `core/` 는 건드리지 말 것 (필요하면 이슈로 말하기)
4. `python tests/test_games.py` 통과 확인 (모든 게임을 자동으로 끝까지 돌려봄)
5. PR(main 대상) 올리고 한 명 리뷰 후 merge

메뉴 등록은 자동이라 공용 파일을 고칠 일이 없음 → merge 충돌 거의 0.
자세한 게임 규칙은 `AGENTS.md`, 공용 도구는 `core/ui.py` · `core/sfx.py` 참고.
