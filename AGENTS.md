# AGENTS.md

축제 할인 쿠폰용 미니게임 모음. Python + pygame-ce, 부스 노트북 한 대에서 키오스크로 실행.
여러 명이 각자 게임을 추가하므로 **충돌 방지 규칙이 최우선**.

## 구조
- `main.py` — 실행 진입점 (`python main.py [--kiosk]`)
- `core/app.py` — 런처. 대기 화면 → 게임 선택 → **경품 먼저 추첨** → 게임에 결과 전달 → 결과(쿠폰) 화면. 관리자 화면(F1) 포함
- `core/store.py` — 확률표(`PRIZES`), 추첨, 쿠폰 발급/사용 처리/통계. SQLite `festival.db` (gitignore됨). **확률·수량은 여기만**
- `core/ui.py` — 공용 UI 키트 (폰트, 텍스트, 패널, 이징, 파티클). 게임에서 import 가능
- `core/sfx.py` — 코드로 합성한 효과음. 게임에서 import 가능
- `games/<게임>.py` — 게임 1개 = 파일 1개. `_` 로 시작하는 파일은 메뉴 제외
- `games/_template.py` — 새 게임 시작점
- `tests/test_games.py` — 규칙 검사 + 모든 게임을 빨리 감기로 끝까지 실행 + 확률/쿠폰 검사 (CI에서 실행)

## 반드시 지킬 것
- 작업 전 `git switch -c game/<게임이름>`. **main에 직접 commit/push 금지**, PR로만 merge. PR은 항상 main 대상 (PR 위에 PR 쌓지 말 것)
- 게임 작업 시 수정 가능한 파일은 **`games/<내게임>.py` 와 `games/assets/<내게임>/` 뿐**
- `main.py`, `core/`, `tests/`, `.github/` 는 게임 작업 중 수정 금지. 필요하면 사람에게 먼저 묻기
- 다른 사람 게임 파일 수정 금지
- 새 의존성 금지. 꼭 필요하면 `requirements.txt` 변경만 별도 PR로

## 게임 인터페이스
```python
NAME = "메뉴에 보일 이름"   # 필수. 다른 게임과 중복 X
TAGLINE = "한 줄 설명"      # 선택
COLOR = (90, 190, 255)      # 선택. 썸네일 없을 때 카드 색

def play(screen, win: bool) -> bool:  # 필수. screen: 800x600 Surface
    ...  # win: 런처가 확률표로 미리 정한 결과. 게임은 거기 맞춰 연출만
         # 끝까지 진행 True, ESC/창닫기 False (경품 없음)
# 경품 이름까지 필요하면 (예: 룰렛) play(screen, win, prize=None) — 런처가 세 번째로 경품 이름을 넘겨줌

def thumbnail() -> pygame.Surface:    # 선택. 메뉴 카드 그림 (비율 8:5 권장)
    ...
```
- 결과를 실력으로 바꾸지 말 것. 당첨/꽝은 `win` 그대로 따름
- 자기 루프 안에서 이벤트 처리. ESC와 `pygame.QUIT` 은 항상 `False` 반환
- 시간은 `pygame.time.get_ticks()` / `pygame.time.Clock` 으로만 (테스트가 시간을 빨리 감음. `time.sleep` 금지)
- 키보드 없이도(마우스 클릭/터치만으로) 끝까지 갈 수 있게 만들기
- `pygame.quit()`, `sys.exit()`, `pygame.display.set_mode()` 호출 금지
- 추첨/쿠폰 직접 처리 금지 — 런처가 처리. `core.app` import 금지, `core.store` 는 `PRIZES`/`LOSE` **읽기만** 가능 (`Store`, 추첨, 기록 금지). `core.ui`, `core.sfx` 는 써도 됨
- 에셋 경로는 `Path(__file__).parent / "assets" / "<내게임>"` 기준

## 확인
```
source .venv/bin/activate
python tests/test_games.py   # PR 전 필수 통과
python main.py               # 실제 플레이 확인
```
