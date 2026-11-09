# AGENTS.md

축제 할인 쿠폰용 미니게임 모음. Python + pygame-ce, 부스 노트북 한 대에서 키오스크로 실행.
여러 명이 각자 게임을 추가하므로 **충돌 방지 규칙이 최우선**.

## 구조
- `main.py` — 런처. `games/*.py` 자동 탐색 → 메뉴 → 게임 실행 → 승리 시 쿠폰 발급
- `coupon.py` — 쿠폰 코드 생성 + `coupons.csv` 기록 (gitignore됨)
- `games/<게임>.py` — 게임 1개 = 파일 1개. `_` 로 시작하는 파일은 메뉴 제외
- `games/_template.py` — 새 게임 시작점
- `tests/test_games.py` — 게임 규칙 검사 (CI에서 실행)

## 반드시 지킬 것
- 작업 전 `git switch -c game/<게임이름>`. **main에 직접 commit/push 금지**, PR로만 merge
- 게임 작업 시 수정 가능한 파일은 **`games/<내게임>.py` 와 `games/assets/<내게임>/` 뿐**
- `main.py`, `coupon.py`, `tests/`, `.github/` 는 게임 작업 중 수정 금지. 필요하면 사람에게 먼저 묻기
- 다른 사람 게임 파일 수정 금지
- 새 의존성 금지. 꼭 필요하면 `requirements.txt` 변경만 별도 PR로

## 게임 인터페이스
```python
NAME = "메뉴에 보일 이름"   # 다른 게임과 중복 X

def play(screen) -> bool:   # screen: 800x600 Surface
    ...                     # 승리 True, 패배/ESC/창닫기 False
```
- 자기 루프 안에서 이벤트 처리. ESC와 `pygame.QUIT` 은 항상 `False` 반환
- `pygame.quit()`, `sys.exit()`, `pygame.display.set_mode()` 호출 금지
- 쿠폰 직접 발급 금지 (`coupon` import 금지) — 런처가 처리
- 에셋 경로는 `Path(__file__).parent / "assets" / "<내게임>"` 기준

## 확인
```
source .venv/bin/activate
python tests/test_games.py   # PR 전 필수 통과
python main.py               # 실제 플레이 확인
```
