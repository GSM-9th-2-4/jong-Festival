# AGENTS.md

축제 할인 쿠폰용 3D 미니게임 모음. **Godot 4.7 (GDScript)**, 부스 노트북 한 대에서 키오스크로 실행.
여러 명이 각자 게임을 추가하므로 **충돌 방지 규칙이 최우선**. (루트의 `main.py`/`core/`/`games/` 는 예전 pygame 버전 — 새 작업은 전부 `godot/` 에서)

## 구조 (`godot/`)
- `main.gd` — 진입점 + 개발용 실행 인자 (`--game= --rank= --auto --shots= --at= --input= --quit`, 파일 맨 위 주석 참고)
- `core/launcher.gd` — 런처: 대기 → 게임 선택 → **경품 먼저 추첨** → 게임 → 결과(쿠폰) → 관리자
- `core/store.gd` — 확률표 `PRIZES`, 추첨, 쿠폰 기록/사용 처리, `rank()`. **확률·수량은 여기만**
- `core/kit.gd` — 공용 도구 `Kit.`: 실사 재질 `pbr()`, 환경 조명 `environment()`, 모델 `model()`, 글꼴 `font()`, 효과음 `sfx()`, 당첨 연출 `celebrate()`, 등급 `TIERS`
- `games/<id>/game.gd` — 게임 1개 = 폴더 1개. `_` 로 시작하는 폴더는 메뉴 제외. `games/_template/` 이 시작점
- `tools/fetch_assets.py` — Poly Haven(CC0) 소재 내려받기. 각 게임의 `assets.json` 을 읽음
- 루트 `play.py` — Godot·소재를 자동으로 준비하고 실행

## 반드시 지킬 것
- 작업 전 `git switch -c game/<게임이름>`. **main에 직접 commit/push 금지**, PR로만 merge. PR은 항상 main 대상 (PR 위에 PR 쌓지 말 것)
- 게임 작업 시 수정 가능한 곳은 **`godot/games/<내게임>/` 뿐**
- `godot/core/`, `godot/main.gd`, `godot/project.godot`, `play.py`, `.github/` 는 게임 작업 중 수정 금지. 필요하면 사람에게 먼저 묻기
- 다른 사람 게임 폴더 수정 금지
- 내려받은 소재(`godot/assets/textures|hdris|models`)는 git에 올리지 않음 (gitignore됨). 글꼴·효과음·`thumb.png` 만 올림

## 게임 규칙 (`games/_template/game.gd` 주석이 원본)
```gdscript
extends Node3D
const NAME := "메뉴에 보일 이름"
const TAGLINE := "한 줄 설명"
signal finished(completed: bool)
var win := false   # 런처가 미리 정해서 넣어줌
var prize := ""    # 경품 이름
var rank := 0      # 등급 0(꽝)~4(크리티컬)
```
- 결과는 이미 정해져 있음. 게임은 그 결과대로 **연출만**. 끝나면 `finished.emit(true)`, ESC는 `finished.emit(false)`
- 마우스 클릭/터치/스페이스만으로 끝까지 갈 수 있어야 함. `Kit.auto` 가 true 면 스스로 진행 (자동 테스트용)
- 추첨/기록 금지: `Store.draw / record / redeem` 호출 금지. `Store.rank()`, `Store.PRIZES` 읽기만
- 당첨 순간: `await get_tree().create_timer(Kit.celebrate(rank, prize)).timeout`
- 소재는 실행 중에 `Kit.pbr / Kit.model / Kit.texture` 로 읽음 (`load("res://…jpg")` 금지 — import 과정이 없음). 필요한 소재 이름은 `games/<id>/assets.json` 에
- 소재가 없어도(안 받은 PC) 게임이 죽지 않게 할 것
- 메뉴 카드 그림: `games/<id>/thumb.png` (1280x720, 글자 없는 장면)

## 화면 글자 규칙
- `Kit.font(weight, tabular)` (Pretendard) 만 사용. 제목 800~900, 본문 500~700, 숫자는 tabular
- 한글 위주. 느낌표 여러 개, 자간 벌린 영문 대문자, 글자 테두리·빛 번짐·그라데이션 금지
- 3D 위 글자는 어두운 판(`Color(0.03, 0.03, 0.04, 0.86)`, 모서리 14~16) 위에. 글자색 `Kit.PAPER`
- 등급 색은 한 화면에 포인트 하나만 (작은 점·선·띠)

## 확인
```
python3 play.py --game=<내게임> --rank=0 --auto --quit   # 0~4 전부: "finished: true" 가 찍히고 에러 없어야 함
python3 play.py --game=<내게임> --rank=3 --auto --shots=shots/<내게임> --at=1,4,8   # 스크린샷으로 눈 확인
python3 play.py                                          # 런처에서 실제 플레이
```
