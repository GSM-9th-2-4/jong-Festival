# 축제 미니게임 (할인 쿠폰)

Python + pygame-ce. 부스 노트북 한 대에서 실행 → 게임 이기면 쿠폰 코드 화면 표시 + `coupons.csv` 기록.

## 실행
```
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

## 게임 추가하는 법 (충돌 안 나는 규칙)
1. `git switch -c game/<내게임>` — main 에 직접 push 금지
2. `games/_template.py` 복사 → `games/<내게임>.py`
3. **내 파일(`games/<내게임>.py`, `games/assets/<내게임>/`)만 수정.** `main.py`, `coupon.py` 는 건드리지 말 것 (필요하면 이슈로 말하기)
4. `python tests/test_games.py` 통과 확인
5. PR 올리고 한 명 리뷰 후 merge

메뉴 등록은 자동이라 공용 파일을 고칠 일이 없음 → merge 충돌 거의 0.

## 게임 규칙
- `NAME = "메뉴에 보일 이름"` (다른 게임과 중복 X)
- `def play(screen) -> bool` — 승리 True, 패배/ESC False
- `pygame.quit()`, `sys.exit()` 호출 금지 / 쿠폰 직접 발급 금지 (런처가 함)
- 새 라이브러리 필요하면 `requirements.txt` 수정은 따로 PR로
