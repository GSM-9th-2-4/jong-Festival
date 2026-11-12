# 종 페스티벌 미니게임 (할인 쿠폰)

축제 부스 노트북에서 돌리는 3D 미니게임 모음. 게임 한 판 → 확률표대로 할인 쿠폰.
Godot 4.7 (3D) 버전이 본편이고, 예전 pygame 버전은 예비로 남겨둠.

게임: 펀치머신 · 레전드 룰렛 · 페널티킥 · 두더지 잡기
확률: 꽝 50% / 500원 25% (레어) / 1,000원 15% (에픽) / 2,000원 8% (전설) / 대박 전액 면제 2% (크리티컬)

## 바로 실행 (맥 · 윈도우 공통)
```
git clone https://github.com/GSM-9th-2-4/jong-Festival.git
cd jong-Festival
python3 play.py          # 윈도우는 python play.py
```
- 또는 폴더에서 **`실행-맥.command`** / **`실행-윈도우.bat`** 더블클릭
- 처음 한 번은 Godot(게임 엔진)과 3D 소재를 알아서 내려받음 — 약 600MB, 3~5분. 그다음부터는 바로 켜짐
- 따로 설치할 것 없음. 필요한 것: Python 3, 인터넷(처음 한 번)
- 부스에서는 `python3 play.py --kiosk` (전체화면, ESC로 못 끔)
- 관리자 PIN 바꾸기: 맥 `FESTIVAL_PIN=4821 python3 play.py --kiosk` / 윈도우 `set FESTIVAL_PIN=4821` 후 실행 (기본 `0000`)

## 부스 운영 (스태프용)
| 조작 | 동작 |
|---|---|
| F1 (또는 대기 화면 왼쪽 위 로고 5번 터치) | 관리자 화면 (PIN 입력) |
| F2 (당첨 화면에서) | 그 쿠폰을 바로 "사용 완료" 처리 |
| F11 | 전체화면 전환 |
| 관리자 화면 F5 / F10 | CSV 내보내기 / 프로그램 종료 |

- 관리자 화면: 경품별 나온 수·실제 확률·사용 완료 수, 쿠폰 코드 입력으로 사용 처리(중복 사용 차단)
- 기록 파일(꽝 포함 전부 저장): 맥 `~/Library/Application Support/Godot/app_userdata/종 페스티벌/festival.json`,
  윈도우 `%APPDATA%\Godot\app_userdata\종 페스티벌\festival.json` — **축제 시작 전에 이 파일을 지우면 초기화**
- 확률·수량 제한은 `godot/core/store.gd` 의 `PRIZES` 만 고치면 됨 (`cap` 에 숫자를 주면 그 수량 뒤로는 꽝)
- 게임 도중 ESC로 나가도 이미 뽑힌 결과는 다음 판에 그대로 (다시 뽑기 불가)

## 게임 추가하는 법 (충돌 안 나는 규칙)
1. `git switch -c game/<내게임>` — main 에 직접 push 금지, PR은 항상 main 대상
2. `godot/games/_template/` 폴더를 복사 → `godot/games/<내게임>/` (규칙은 `game.gd` 맨 위 주석과 `AGENTS.md`)
3. **내 폴더(`godot/games/<내게임>/`)만 수정.** `godot/core/`, `godot/main.gd` 는 건드리지 말 것
4. 혼자 돌려보기: `python3 play.py --game=<내게임> --rank=2` (등급 0=꽝 ~ 4=크리티컬), 자동 진행 확인은 `--auto --quit` 추가
5. PR 올리고 한 명 리뷰 후 merge

메뉴 등록은 자동 (폴더만 있으면 뜸) → 공용 파일을 고칠 일이 없어서 merge 충돌이 거의 없음.

## 폴더
- `play.py` — 한 번에 실행 (Godot·소재 자동 준비)
- `godot/` — 3D 버전: `core/`(런처·공용 도구·확률표), `games/<게임>/`, `tools/fetch_assets.py`
- `main.py`, `core/`, `games/`, `tests/` — 예전 pygame 버전 (`pip install -r requirements.txt && python main.py`)

## 소재 출처
3D 재질·환경 조명·소품: Poly Haven (CC0) · 사람 모델: Microsoft Rocketbox (MIT, `godot/games/penalty/CREDITS.md`) · 글꼴: Pretendard (SIL OFL, `godot/assets/fonts/OFL.txt`)
