"""무료(CC0) 3D 소재 내려받기 — Poly Haven (https://polyhaven.com, CC0 라이선스).

사용: python3 godot/tools/fetch_assets.py
godot/core/assets.json 과 godot/games/*/assets.json 을 전부 읽어서 godot/assets/ 아래로 받음 (이미 있으면 건너뜀).
assets.json 형식: {"textures": ["leather_red_02", {"id": "concrete_floor", "res": "2k"}], "hdris": ["studio_small_03"], "models": ["football"]}
소재 이름은 polyhaven.com 주소의 마지막 부분 (예: polyhaven.com/a/football → "football").
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets"
UA = "festival-minigame-dev"


def get(url):
    # curl 사용: 파이썬 기본 설치에 인증서가 없는 PC가 많음 (mac/윈도우 10+ 에는 curl 이 기본 포함)
    return subprocess.run(["curl", "-fsSL", "--max-time", "120", "-A", UA, url], check=True, capture_output=True).stdout


def save(url, path):
    if path.exists() and path.stat().st_size > 0:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(get(url))
    print("  +", path.relative_to(ROOT))


def fetch(kind, entry):
    asset, res = (entry, None) if isinstance(entry, str) else (entry["id"], entry.get("res"))
    files = json.loads(get(f"https://api.polyhaven.com/files/{asset}"))
    if kind == "hdris":
        save(files["hdri"][res or "2k"]["hdr"]["url"], OUT / "hdris" / f"{asset}.hdr")
        return
    pack = files["gltf"][res or "1k"]["gltf"]  # gltf 묶음: 모델/재질 + 색·노멀·ARM 텍스처
    base = OUT / kind / asset
    save(pack["url"], base / f"{asset}.gltf")
    for rel, inc in pack.get("include", {}).items():
        save(inc["url"], base / rel)


def main():
    manifests = [ROOT / "core" / "assets.json"] + sorted((ROOT / "games").glob("*/assets.json"))
    seen, failed = set(), []
    for m in manifests:
        if not m.exists():
            continue
        for kind, entries in json.loads(m.read_text()).items():
            for e in entries:
                key = (kind, json.dumps(e, sort_keys=True))
                if key in seen:
                    continue
                seen.add(key)
                try:
                    fetch(kind, e)
                except Exception as ex:  # 하나 실패해도 나머지는 계속
                    failed.append(f"{m.relative_to(ROOT)}: {kind} {e} → {ex}")
    for f in failed:
        print("실패:", f, file=sys.stderr)
    print(f"완료: {len(seen) - len(failed)}개 확인, {len(failed)}개 실패")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
