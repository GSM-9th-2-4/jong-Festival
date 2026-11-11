extends Node
## 경품 확률표 + 쿠폰 저장 (어디서든 `Store.`). 게임은 rank()/PRIZES 읽기만 — 추첨/기록은 런처만.
## 기록 파일: user://festival.json (맥: ~/Library/Application Support/Godot/app_userdata/종 페스티벌/)

const LOSE := "꽝"
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # 0/O/1/I 헷갈림 방지
const PRIZES := [  # 확률(%) 합 100. cap: 최대 수량(-1 = 무제한, 다 나가면 꽝 처리)
	{"name": "꽝", "pct": 50, "cap": -1},
	{"name": "대박! 전액 면제", "pct": 2, "cap": -1},
	{"name": "500원 할인", "pct": 25, "cap": -1},
	{"name": "1,000원 할인", "pct": 15, "cap": -1},
	{"name": "2,000원 할인", "pct": 8, "cap": -1},
]
const PATH := "user://festival.json"

var plays: Array = []  # {ts, game, prize, code, redeemed_at}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if FileAccess.file_exists(PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if data is Array:
			plays = data


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(plays))
	f.close()


## 등급: 꽝 0, 당첨은 확률 높은 순서로 1(레어) 2(에픽) 3(전설) 4(크리티컬)
func rank(prize: String) -> int:
	var wins := PRIZES.filter(func(p): return p["name"] != LOSE)
	wins.sort_custom(func(a, b): return a["pct"] > b["pct"])
	for i in wins.size():
		if wins[i]["name"] == prize:
			return i + 1
	return 0


func prize_of_rank(r: int) -> String:
	for p in PRIZES:
		if rank(p["name"]) == r:
			return p["name"]
	return LOSE


func count(prize: String) -> int:
	return plays.filter(func(p): return p["prize"] == prize).size()


func draw() -> String:
	var roll := _rng.randf() * 100.0
	for p in PRIZES:
		roll -= p["pct"]
		if roll < 0.0:
			if p["cap"] >= 0 and count(p["name"]) >= p["cap"]:
				return LOSE
			return p["name"]
	return LOSE


## 플레이 기록. 당첨이면 쿠폰 코드, 꽝이면 "" 반환.
func record(game: String, prize: String) -> String:
	var code := ""
	if prize != LOSE:
		while code == "" or plays.any(func(p): return p["code"] == code):
			code = ""
			for i in 6:
				code += ALPHABET[_rng.randi() % ALPHABET.length()]
	plays.append({"ts": Time.get_datetime_string_from_system(), "game": game, "prize": prize, "code": code, "redeemed_at": ""})
	_save()
	return code


## 쿠폰 사용 처리 → {"status": "ok" | "used" | "none", "prize", "at"}
func redeem(code: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	for p in plays:
		if code != "" and p["code"] == code:
			if p["redeemed_at"] != "":
				return {"status": "used", "prize": p["prize"], "at": p["redeemed_at"]}
			p["redeemed_at"] = Time.get_datetime_string_from_system()
			_save()
			return {"status": "ok", "prize": p["prize"], "at": p["redeemed_at"]}
	return {"status": "none", "prize": "", "at": ""}
