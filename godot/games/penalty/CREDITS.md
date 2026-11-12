# 페널티킥 — 소재 출처

## 사람 모델 (골키퍼·키커)

| 쓰임 | 모델 | 받는 폴더 (git 에 올리지 않음) |
|---|---|---|
| 골키퍼 | Microsoft Rocketbox Avatar Library — `Sports_Male_02` (텍스처 `m301`) | `godot/assets/models/rocketbox_sports_male_02/` |
| 키커 | Microsoft Rocketbox Avatar Library — `Sports_Male_03` (텍스처 `m300`) | `godot/assets/models/rocketbox_sports_male_03/` |

- 출처: https://github.com/microsoft/Microsoft-Rocketbox
  - `Assets/Avatars/Professions/Sports_Male_02/` , `Assets/Avatars/Professions/Sports_Male_03/` (FBX + TGA 텍스처)
- 라이선스: **MIT License**, Copyright (c) 2020 Microsoft
  (https://github.com/microsoft/Microsoft-Rocketbox/blob/master/LICENSE.md — 받을 때 각 모델 폴더에 `LICENSE.md` 로 같이 저장됨.
  배포물에 모델을 넣을 때는 이 저작권·허가 문구를 함께 넣어야 함)
- 받는 법: `python3 godot/games/penalty/fetch_keeper.py` (curl 로 raw.githubusercontent.com 에서 받음, 로그인·키 필요 없음, 약 105MB)
- 바꾼 것 (파일은 그대로 두고 실행 중에만):
  - 골키퍼: 셰이더로 상의·양말을 노란 골키퍼 유니폼 색으로 물들이고, 손 부분을 흰 장갑으로 칠함 (`human.gd` 의 `SHADER`)
  - 키커: 원래 줄무늬 유니폼 그대로
  - 동작은 모델에 든 애니메이션이 아니라 뼈대(Bip01)를 코드로 직접 움직임 (`human.gd`, `keeper_human.gd`, `kicker.gd`)
- 모델 파일이 없으면 게임은 `keeper.gd` 의 캡슐 인형으로 대신 돌아감.

## 그 밖

- 공·잔디·천 재질·밤하늘: Poly Haven (CC0) — `assets.json`, `godot/tools/fetch_assets.py`
- 글꼴: Pretendard (SIL OFL 1.1) — `Kit.font()`
