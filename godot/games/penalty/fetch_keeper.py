"""페널티킥 골키퍼·키커용 사람 모델 내려받기 — Microsoft Rocketbox Avatar Library (MIT 라이선스).

사용: python3 godot/games/penalty/fetch_keeper.py
godot/assets/models/rocketbox_sports_male_02/ (골키퍼), rocketbox_sports_male_03/ (키커) 아래로 받음
(이미 있으면 건너뜀, 합쳐서 약 105MB). 모델이 없어도 게임은 돌아감 — 그때는 예전 캡슐 인형으로 대신함.
출처/라이선스는 같은 폴더의 CREDITS.md 참고.
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "models"
BASE = "https://raw.githubusercontent.com/microsoft/Microsoft-Rocketbox/master/"
AVATARS = BASE + "Assets/Avatars/Professions/"
UA = "festival-minigame-dev"
# (받을 폴더, 원본 아바타, 텍스처 접두어, 텍스처 종류)
MODELS = [
    ("rocketbox_sports_male_02", "Sports_Male_02", "m301", ["body_color", "body_normal", "head_color", "head_normal"]),  # 골키퍼
    ("rocketbox_sports_male_03", "Sports_Male_03", "m300", ["body_color", "body_normal", "head_color", "head_normal", "opacity_color"]),  # 키커
]
FILES = {}
for folder, avatar, prefix, kinds in MODELS:
    FILES[f"{folder}/{avatar}.fbx"] = f"{AVATARS}{avatar}/Export/{avatar}.fbx"
    for kind in kinds:
        FILES[f"{folder}/{prefix}_{kind}.tga"] = f"{AVATARS}{avatar}/Textures/{prefix}_{kind}.tga"
    FILES[f"{folder}/LICENSE.md"] = BASE + "LICENSE.md"


def main():
    failed = []
    for name, url in FILES.items():
        path = OUT / name
        if path.exists() and path.stat().st_size > 0:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + ".part")
        # curl 사용: 파이썬 기본 설치에 인증서가 없는 PC가 많음
        r = subprocess.run(["curl", "-fsSL", "--max-time", "300", "-A", UA, "-o", str(tmp), url])
        if r.returncode != 0 or not tmp.exists() or tmp.stat().st_size == 0:
            tmp.unlink(missing_ok=True)
            failed.append(name)
            continue
        tmp.replace(path)
        print("  +", path.relative_to(ROOT))
    for f in failed:
        print("실패:", f, file=sys.stderr)
    print(f"완료: {len(FILES) - len(failed)}개 확인, {len(failed)}개 실패")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
