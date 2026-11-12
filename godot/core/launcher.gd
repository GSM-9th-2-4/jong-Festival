extends Node
## 런처(키오스크). 대기 화면 → 게임 선택 → 추첨 → 게임 → 결과 → 대기 화면.
##
## 실행: godot --path godot [-- --kiosk]
##   --kiosk : 전체화면 + ESC/창닫기로 종료 불가 (종료는 관리자 화면 F10)
## 키: F1 관리자(PIN, 환경변수 FESTIVAL_PIN / 기본 0000) · F11 전체화면 · 당첨 화면에서 F2 = 그 자리에서 쿠폰 사용 처리
##     터치만 있을 때: 대기 화면 왼쪽 위 로고를 빠르게 5번 누르면 관리자
##
## 개발/테스트용 인자 (전부 `--` 뒤에):
##   --screen=attract|menu|result|pin|admin   그 화면에서 시작 (admin 은 PIN 생략)
##   --force-rank=<0~4>     추첨 대신 그 등급으로 고정 (0 = 꽝)
##   --pick=<번호|폴더명>    --auto 일 때 고를 게임 (기본 0)
##   --auto                 대기 → 메뉴 → 게임 → 결과를 스스로 진행 (Kit.auto)
##   --dry                  기록 파일(user://festival.json)을 건드리지 않음: 가짜 코드, 메모리 안에서만 기록/사용 처리
##                          (--shots 나 --auto 가 있으면 자동으로 켜짐. 그래도 진짜로 기록하려면 --live)
##   --demo                 (dry 전용) 관리자 화면 확인용 가짜 기록 140판. 코드 AAAAAA = 미사용, BBBBBB = 사용됨
##   --dev-games            '_' 로 시작하는 폴더(_template)도 메뉴에 표시
##   --fake-games=<N>       메뉴 배치 확인용으로 가짜 카드 N개 추가
##   --broken-game          일부러 깨진 게임 카드를 하나 추가 (오류가 나도 메뉴로 돌아오는지 확인용)
##   --keys=<초>:<키>;...    그 시각에 입력 흉내. 키 이름(F1, Enter, Escape, Right…), 글자열(0000, AAAAAA), click@x,y, result=<등급>(결과 화면 미리보기)
##                          (--keys 나 --shots 가 있으면 진짜 키보드/마우스 입력은 무시 — 자동 실행 중 사람 손이 닿아도 안 흔들리게)
##                          예) --keys="1:F1;2:0000;2.5:Enter;4:AAAAAA;4.5:Enter;6:F5"

const Backdrop := preload("res://core/launcher/backdrop.gd")
const UI := preload("res://core/launcher/ui.gd")

const W := 1280.0
const H := 720.0
const TITLE := "종 페스티벌"
const BRAND := "JONG FESTIVAL"
const IDLE_MENU := 30.0       # 메뉴에서 입력 없으면 대기 화면으로
const IDLE_ADMIN := 120.0     # 관리자 화면을 열어둔 채 자리를 비우면 닫힘
const RESULT_LOCK := 1.5      # 결과 화면 연타 스킵 방지
const GAME_STALL := 150.0     # 게임 중 이만큼 아무 입력이 없으면(멈춘 게임/떠난 손님) 메뉴로
const COLS := 4
const PER_PAGE := 8
const CARD_HUES := [Color(0.12, 0.3, 0.62), Color(0.42, 0.18, 0.58), Color(0.6, 0.38, 0.1), Color(0.58, 0.13, 0.2), Color(0.08, 0.42, 0.42), Color(0.3, 0.34, 0.5)]

var games: Array = []       # {id, name, tagline, path, thumb}
var sel := 0
var pending := ""           # 뽑아놓고 아직 안 쓴 경품 (게임 중 ESC 로 다시 뽑기 방지)
var last_prize := ""
var last_code := ""
var kiosk := false
var dry := false

var _args := {}
var _pin := "0000"
var _dry_plays: Array = []
var _state := ""
var _t := 0.0
var _idle := 0.0
var _busy := false
var _game: Node
var _game_name := ""

var _back: Node3D
var _ui: CanvasLayer
var _dim: ColorRect
var _holder: Control
var _screen: Control
var _right: Label
var _hints: HBoxContainer
var _top: CanvasLayer
var _fade: ColorRect
var _toast_box: Control

# 화면별 상태
var _tier_hl: Array = []
var _hot := -1
var _cards: Array = []
var _grid: Control
var _page := -1
var _counter: Label
var _dots: Control
var _bar: ColorRect
var _timeout := 9.0
var _ticket: Control
var _redeemed := false
var _typed := ""
var _pin_panel: Panel
var _pin_dots: Control
var _admin_stats: Control
var _code_label: Label
var _msg: Label
var _taps: Array = []
var _fake_only := false   # 자동 실행 중: 흉내 낸 입력만 받음
var _faking := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	kiosk = _args.has("kiosk")
	_fake_only = _args.has("shots") or _args.has("keys")
	dry = (_args.has("dry") or _args.has("shots") or _args.has("auto")) and not _args.has("live")
	var env_pin := OS.get_environment("FESTIVAL_PIN").strip_edges()
	if env_pin != "":
		_pin = env_pin
	if dry:
		_dry_plays = Store.plays.duplicate(true)
		if _args.has("demo"):
			_seed_demo()
		print("[launcher] dry 모드: 기록 파일을 건드리지 않음")
	if kiosk:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_tree().auto_accept_quit = false
	_discover()

	_back = Backdrop.new()
	add_child(_back)
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)
	_dim = UI.rect(_ui, Rect2(0, 0, W, H), Color(0.01, 0.012, 0.03, 0.0))
	UI.gradient(_ui, Rect2(0, 0, W, 150), [[0.0, Color(0, 0, 0.02, 0.6)], [1.0, Color(0, 0, 0.02, 0.0)]])
	UI.gradient(_ui, Rect2(0, H - 170, W, 170), [[0.0, Color(0, 0, 0.02, 0.0)], [1.0, Color(0, 0, 0.02, 0.7)]])
	_holder = Control.new()
	_holder.size = Vector2(W, H)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_holder)
	UI.text(_ui, BRAND, 15, Vector2(56, 37), UI.WHITE, false, 2, -1, false, 800)  # 화면에 하나뿐인 영문 대문자 라벨
	_right = UI.text(_ui, "", 16, Vector2(W - 56, 36), UI.GRAY, false, 0, 1, false, 600)
	UI.rect(_ui, Rect2(56, 70, W - 112, 1), UI.LINE)
	UI.rect(_ui, Rect2(56, 69, 84, 2), Kit.GOLD)
	_hints = HBoxContainer.new()
	_hints.position = Vector2(0, 668)
	_hints.size = Vector2(W, 34)
	_hints.alignment = BoxContainer.ALIGNMENT_CENTER
	_hints.add_theme_constant_override("separation", 34)
	_ui.add_child(_hints)

	_top = CanvasLayer.new()
	_top.layer = 60
	add_child(_top)
	_toast_box = Control.new()
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_toast_box)
	_fade = UI.rect(_top, Rect2(0, 0, W, H), Color(0, 0, 0, 1))
	create_tween().tween_property(_fade, "color:a", 0.0, 0.6)

	var first: String = _args.get("screen", "attract")
	if first == "result":
		last_prize = _forced() if _forced() != "" else Store.prize_of_rank(1)
		last_code = _record("미리보기", last_prize)
	if first not in ["attract", "menu", "result", "pin", "admin"]:
		first = "attract"
	_goto(first)
	if _args.has("keys"):
		_schedule_keys(_args["keys"])


# ---------- 게임 목록 ----------

func _discover() -> void:
	var found: Array = []
	var hidden: Array = []
	for d in DirAccess.get_directories_at("res://games"):
		var path := "res://games/%s/game.gd" % d
		if not FileAccess.file_exists(path):
			continue
		var e := {"id": d, "name": d, "tagline": "", "path": path, "thumb": null}
		var script = load(path)  # 게임 하나가 깨져 있어도 부스는 계속 돌아가야 함
		if not (script is Script) or not (script as Script).can_instantiate():
			push_warning("[skip] games/%s/game.gd 를 읽을 수 없음" % d)
			continue
		var consts: Dictionary = (script as Script).get_script_constant_map()
		e["name"] = str(consts.get("NAME", d))
		e["tagline"] = str(consts.get("TAGLINE", ""))
		var thumb := ProjectSettings.globalize_path("res://games/%s/thumb.png" % d)
		if FileAccess.file_exists(thumb):
			var img := Image.load_from_file(thumb)
			if img != null:
				img.generate_mipmaps()
				e["thumb"] = ImageTexture.create_from_image(img)
		if d.begins_with("_"):
			hidden.append(e)
		else:
			found.append(e)
	found.sort_custom(func(a, b): return a["id"] < b["id"])
	if _args.has("dev-games") or found.is_empty():
		if found.is_empty() and not hidden.is_empty() and not _args.has("dev-games"):
			push_warning("games/ 에 게임이 없어서 템플릿을 대신 표시")
		found.append_array(hidden)
	for i in int(_args.get("fake-games", "0")):
		found.append({"id": "fake%d" % i, "name": ["별똥별 잡기", "행운의 문", "스피드 퀴즈", "보물 상자", "풍선 터뜨리기", "카드 뒤집기", "주사위 왕", "미로 탈출"][i % 8], "tagline": "배치 확인용 카드", "path": "res://games/_template/game.gd", "thumb": null})
	if _args.has("broken-game"):
		found.append({"id": "broken", "name": "깨진 게임", "tagline": "오류 처리 확인용", "path": "res://games/_nope/game.gd", "thumb": null})
	games = found


# ---------- 기록 (dry 모드에서는 메모리 안에서만) ----------

func _plays() -> Array:
	return _dry_plays if dry else Store.plays


func _record(game: String, prize: String) -> String:
	if not dry:
		return Store.record(game, prize)
	var code := ""
	if prize != Store.LOSE:
		for i in 6:
			code += Store.ALPHABET[randi() % Store.ALPHABET.length()]
	_dry_plays.append({"ts": Time.get_datetime_string_from_system(), "game": game, "prize": prize, "code": code, "redeemed_at": ""})
	return code


func _redeem(code: String) -> Dictionary:
	if not dry:
		return Store.redeem(code)
	code = code.strip_edges().to_upper()
	for p in _dry_plays:
		if code != "" and p["code"] == code:
			if p["redeemed_at"] != "":
				return {"status": "used", "prize": p["prize"], "at": p["redeemed_at"]}
			p["redeemed_at"] = Time.get_datetime_string_from_system()
			return {"status": "ok", "prize": p["prize"], "at": p["redeemed_at"]}
	return {"status": "none", "prize": "", "at": ""}


func _seed_demo() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var names := ["펀치머신", "룰렛", "승부차기", "두더지 잡기"]
	_dry_plays.append({"ts": "2026-11-12T10:00:00", "game": names[0], "prize": Store.prize_of_rank(2), "code": "AAAAAA", "redeemed_at": ""})
	_dry_plays.append({"ts": "2026-11-12T10:01:00", "game": names[1], "prize": Store.prize_of_rank(1), "code": "BBBBBB", "redeemed_at": "2026-11-12T10:07:42"})
	for i in 138:
		var roll := rng.randf() * 100.0
		var prize: String = Store.LOSE
		for p in Store.PRIZES:
			roll -= p["pct"]
			if roll < 0.0:
				prize = p["name"]
				break
		var code := ""
		if prize != Store.LOSE:
			for j in 6:
				code += Store.ALPHABET[rng.randi() % Store.ALPHABET.length()]
		_dry_plays.append({"ts": "2026-11-12T10:%02d:%02d" % [2 + i / 3, (i * 20) % 60], "game": names[rng.randi() % 4 if rng.randf() < 0.8 else 0], "prize": prize, "code": code,
			"redeemed_at": "2026-11-12T11:00:00" if code != "" and rng.randf() < 0.4 else ""})


func _export_csv() -> String:
	var path := "user://coupons_dry.csv" if dry else "user://coupons.csv"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	var q := func(v) -> String: return "\"" + str(v).replace("\"", "\"\"") + "\""
	var out := "﻿" + "시각,게임,경품,코드,사용시각\r\n"  # BOM: 엑셀에서 한글이 깨지지 않게
	for p in _plays():
		out += ",".join([q.call(p.get("ts", "")), q.call(p.get("game", "")), q.call(p.get("prize", "")), q.call(p.get("code", "")), q.call(p.get("redeemed_at", ""))]) + "\r\n"
	f.store_string(out)
	f.close()
	var real := ProjectSettings.globalize_path(path)
	print("[launcher] CSV 내보냄: ", real)
	return real


func _forced() -> String:
	if _args.has("force-rank"):
		return Store.prize_of_rank(clampi(int(_args["force-rank"]), 0, Kit.TOP_TIER))
	return ""


# ---------- 공통 ----------

func _goto(state: String) -> void:
	_state = state
	_t = 0.0
	_idle = 0.0
	_typed = ""
	var scr := Control.new()
	scr.size = Vector2(W, H)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match state:
		"attract": _build_attract(scr)
		"menu": _build_menu(scr)
		"result": _build_result(scr)
		"pin": _build_pin(scr)
		"admin": _build_admin(scr)
	var old := _screen
	_screen = scr
	_holder.add_child(scr)
	scr.modulate.a = 0.0
	scr.position.y = 14.0
	var tw := scr.create_tween().set_parallel()
	tw.tween_property(scr, "modulate:a", 1.0, 0.4).set_delay(0.12)
	tw.tween_property(scr, "position:y", 0.0, 0.5).set_delay(0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if old != null:
		old.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
		var t2 := old.create_tween()
		t2.tween_property(old, "modulate:a", 0.0, 0.2)
		t2.tween_callback(old.queue_free)


func _set_dim(a: float) -> void:
	create_tween().tween_property(_dim, "color:a", a, 0.6)


func _set_hints(items: Array) -> void:  # [[키, 설명, 눌렀을 때(선택)], ...]
	for c in _hints.get_children():
		c.queue_free()
	for it in items:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", _chip_style())
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := Label.new()
		k.text = it[0]
		k.label_settings = UI.settings(14, UI.WHITE, true, 0, false, 700)
		chip.add_child(k)
		box.add_child(chip)
		var l := Label.new()
		l.text = it[1]
		l.label_settings = UI.settings(17, UI.GRAY, false, 0, true)
		box.add_child(l)
		if it.size() > 2:
			var cb: Callable = it[2]
			box.mouse_filter = Control.MOUSE_FILTER_STOP
			box.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			box.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					cb.call())
		_hints.add_child(box)


func _chip_style() -> StyleBoxFlat:
	var sb := UI.flat(Color(1, 1, 1, 0.07), 6, Color(1, 1, 1, 0.28), 1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _toast(msg: String, color := Color(0.62, 0.14, 0.2, 0.96)) -> void:
	for c in _toast_box.get_children():
		c.queue_free()
	var p := UI.panel(_toast_box, Rect2(W / 2 - 330, 9, 660, 54), UI.flat(color, 27, Color(1, 1, 1, 0.3), 1))
	UI.text(p, msg, 20, Vector2(330, 14), UI.WHITE, false, 0, 0)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _fade_to(a: float, time := 0.3) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, time)
	await tw.finished


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and kiosk:
		_toast("종료는 관리자 화면(F1)에서 F10")
	elif what == NOTIFICATION_PREDELETE and is_instance_valid(_back) and not _back.is_inside_tree():
		_back.free()  # 게임 도중 종료: 트리에서 빼 둔 무대를 직접 정리


func _key_char(e: InputEventKey) -> String:  # 한/영 상태와 무관하게 키 위치로 읽음
	var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
	if (k >= KEY_A and k <= KEY_Z) or (k >= KEY_0 and k <= KEY_9):
		return char(k)
	if k >= KEY_KP_0 and k <= KEY_KP_9:
		return str(k - KEY_KP_0)
	return ""


func _process(delta: float) -> void:
	_t += delta
	_idle += delta
	if _busy:
		return
	match _state:
		"attract":
			var hot := int(_t / 1.6) % maxi(1, _tier_hl.size())
			if hot != _hot and not _tier_hl.is_empty():
				_hot = hot
				for i in _tier_hl.size():
					if is_instance_valid(_tier_hl[i]):
						(_tier_hl[i] as Control).create_tween().tween_property(_tier_hl[i], "modulate:a", 1.0 if i == hot else 0.0, 0.5)
			if Kit.auto and _t > 1.5:
				_goto("menu")
		"menu":
			if Kit.auto and _t > 1.5:
				sel = _pick_index()
				_start_game()
			elif _idle > IDLE_MENU:
				_goto("attract")
		"result":
			if is_instance_valid(_bar):
				_bar.size.x = W * clampf(1.0 - _t / _timeout, 0.0, 1.0)
			if _t > _timeout:
				_goto("attract")
		"pin", "admin":
			if _idle > IDLE_ADMIN:
				_goto("attract")
		"game":
			if _idle > GAME_STALL and not Kit.auto:
				_toast("입력이 없어서 메뉴로 돌아왔어요")
				_end_game(false)


func _input(e: InputEvent) -> void:
	if _fake_only and not _faking:
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey or e is InputEventMouse or e is InputEventScreenTouch or e is InputEventJoypadButton:
		_idle = 0.0
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.keycode if e.keycode != 0 else e.physical_keycode
		if k == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if _state == "game":
			return
		get_viewport().set_input_as_handled()
		if _busy or k in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
			return
		match _state:
			"attract": _key_attract(k)
			"menu": _key_menu(k)
			"result": _key_result(k)
			"pin": _key_pin(k, e)
			"admin": _key_admin(k, e)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _busy:
		if _state == "attract":
			get_viewport().set_input_as_handled()
			if Rect2(0, 0, 320, 72).has_point(e.position):  # 로고 5번 = 관리자 (키보드 없이)
				var now := Time.get_ticks_msec()
				_taps = _taps.filter(func(t): return now - t < 3000)
				_taps.append(now)
				if _taps.size() >= 5:
					_taps.clear()
					_goto("pin")
				return
			Kit.sfx("click")
			_goto("menu")
		elif _state == "result" and _t > RESULT_LOCK:
			get_viewport().set_input_as_handled()
			_goto("attract")


# ---------- 대기 화면 ----------

func _build_attract(scr: Control) -> void:
	_right.text = "할인 쿠폰 이벤트"
	_set_hints([])
	_set_dim(0.0)
	_back.set_mode(-1.75)
	_tier_hl.clear()
	_hot = -1
	UI.gradient(scr, Rect2(0, 0, 900, H), [[0.0, Color(0, 0, 0.02, 0.7)], [1.0, Color(0, 0, 0.02, 0.0)]], Vector2(0, 0), Vector2(1, 0))
	UI.text(scr, TITLE, 136, Vector2(74, 128), UI.WHITE, false, -4, -1, false, 900)
	UI.text(scr, "게임 한 판, 할인 쿠폰 한 장", 34, Vector2(80, 300), Color(UI.WHITE, 0.86), false, 0, -1, false, 500)

	var prizes: Array = []
	for p in Store.PRIZES:
		if Store.rank(p["name"]) > 0:
			prizes.append(p["name"])
	prizes.sort_custom(func(a, b): return Store.rank(a) < Store.rank(b))
	var n := prizes.size()
	var gap := 16.0
	var cw := (W - 160.0 - gap * (n - 1)) / maxf(1, n)
	UI.text(scr, "오늘의 경품", 18, Vector2(82, 432), UI.GRAY, false, 0, -1, false, 600)
	for i in n:
		var t: Dictionary = Kit.tier(Store.rank(prizes[i]))
		var c: Color = t["color"]
		var r := Rect2(80 + i * (cw + gap), 466, cw, 108)
		var g := UI.glass(scr, r, 12, Color(1, 1, 1, 0.1), 0.72)
		var hl := UI.panel(g, Rect2(Vector2.ZERO, r.size), UI.outline(Color(UI.WHITE, 0.75), 12, 2))
		hl.modulate.a = 0.0
		_tier_hl.append(hl)
		UI.panel(g, Rect2(22, 25, 10, 10), UI.flat(c, 3))  # 등급 색은 이 작은 표식 하나에만
		UI.text(g, "%s 등급" % t["kor"], 16, Vector2(42, 19), UI.GRAY, false, 0, -1, false, 600)
		var pl := UI.text(g, prizes[i], 28, Vector2(21, 52), UI.WHITE, false, 0, -1, false, 800)
		while pl.label_settings.font_size > 18 and pl.get_minimum_size().x > cw - 40:
			pl.label_settings.font_size -= 1

	var press := UI.text(scr, "화면을 터치하거나 아무 키나 누르면 시작해요", 26, Vector2(W / 2, 622), UI.WHITE, false, 0, 0, false, 700)
	var tw := press.create_tween().set_loops()
	tw.tween_property(press, "modulate:a", 0.45, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(press, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)


func _key_attract(k: int) -> void:
	if k == KEY_F1:
		_goto("pin")
	elif k == KEY_ESCAPE:
		if not kiosk:
			get_tree().quit()
	else:
		Kit.sfx("click")
		_goto("menu")


# ---------- 게임 선택 ----------

func _build_menu(scr: Control) -> void:
	_right.text = "게임 선택"
	_set_dim(0.42)
	_back.set_mode(0.0, Backdrop.WARM, 0.16)
	sel = clampi(sel, 0, maxi(0, games.size() - 1))
	UI.text(scr, "게임을 골라주세요", 42, Vector2(56, 92), UI.WHITE, false, 0, -1, false, 800)
	if not pending.is_empty():
		UI.text(scr, "이어서 도전하세요. 어떤 게임을 골라도 결과는 같아요", 18, Vector2(58, 150), UI.GRAY, false, 0, -1, true)
	_counter = UI.text(scr, "", 42, Vector2(W - 104, 92), UI.WHITE, true, 0, 1, false, 800)
	UI.text(scr, "/ %02d" % games.size(), 20, Vector2(W - 96, 114), UI.GRAY, true, 0, -1, false, 600)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_grid)
	_dots = Control.new()
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_dots)
	if games.size() > PER_PAGE:
		UI.button(scr, Rect2(8, 372, 40, 72), "‹", 34, true, func(): _move(-PER_PAGE))
		UI.button(scr, Rect2(W - 48, 372, 40, 72), "›", 34, true, func(): _move(PER_PAGE))
	_set_hints([["←  →", "선택"], ["Enter", "시작", _start_game], ["Esc", "처음으로", func(): _goto("attract")]])
	_page = -1
	if games.is_empty():
		UI.text(scr, "games/ 폴더에 게임이 없어요", 28, Vector2(W / 2, 340), UI.GRAY, false, 0, 0)
		return
	_refresh_menu(false)


func _card_rects(count: int) -> Array:
	var big := count <= COLS
	var cw := 300.0 if count <= 3 else 270.0
	var ch := 408.0 if big else 208.0
	var gap := 24.0 if big else 20.0
	var rows := 1 if big else int(ceil(count / float(COLS)))
	var top := 412.0 - (rows * ch + (rows - 1) * gap) / 2.0
	var out: Array = []
	for i in count:
		var row := i / COLS
		var col := i % COLS
		var n := mini(COLS, count - row * COLS)
		var x0 := W / 2 - (n * cw + (n - 1) * gap) / 2.0
		out.append(Rect2(x0 + col * (cw + gap), top + row * (ch + gap), cw, ch))
	return out


func _refresh_menu(animate := true) -> void:
	var page := sel / PER_PAGE
	if page != _page:
		_page = page
		for c in _grid.get_children():
			c.queue_free()
		for c in _dots.get_children():
			c.queue_free()
		_cards.clear()
		var shown := games.slice(page * PER_PAGE, (page + 1) * PER_PAGE)
		var rects := _card_rects(shown.size())
		for i in shown.size():
			_cards.append(_make_card(page * PER_PAGE + i, shown[i], rects[i]))
		var pages := (games.size() - 1) / PER_PAGE + 1
		if pages > 1:
			for p in pages:
				UI.panel(_dots, Rect2(W / 2 - (pages - 1) * 11 + p * 22 - 5, 642, 10, 10), UI.flat(Kit.GOLD if p == page else Color(1, 1, 1, 0.22), 5))
		animate = false
	_counter.text = "%02d" % (sel + 1)
	for card in _cards:
		var on: bool = card.get_meta("index") == sel
		var targets := [[card, "scale", Vector2(1.045, 1.045) if on else Vector2.ONE], [card.get_node("glow"), "modulate:a", 1.0 if on else 0.0],
			[card.get_node("body/veil"), "color:a", 0.0 if on else 0.32], [card.get_node("sel"), "modulate:a", 1.0 if on else 0.0]]
		card.z_index = 1 if on else 0
		if animate:
			var tw: Tween = card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			for t in targets:
				tw.tween_property(t[0], t[1], t[2], 0.22)
		else:
			for t in targets:
				(t[0] as Node).set_indexed(t[1], t[2])


func _make_card(index: int, g: Dictionary, r: Rect2) -> Control:
	var size := r.size
	var card := Control.new()
	card.position = r.position
	card.size = size
	card.pivot_offset = size / 2
	card.set_meta("index", index)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_grid.add_child(card)

	var glow_sb := UI.outline(Color(0, 0, 0, 0), 16, 0)
	glow_sb.shadow_color = Color(0, 0, 0, 0.55)  # 고른 카드는 떠오른 듯한 그림자 (빛 번짐 아님)
	glow_sb.shadow_size = 26
	glow_sb.shadow_offset = Vector2(0, 12)
	var glow := UI.panel(card, Rect2(Vector2.ZERO, size), glow_sb)
	glow.name = "glow"

	var body := UI.panel(card, Rect2(Vector2.ZERO, size), UI.flat(Color(0.04, 0.045, 0.07), 16))
	body.name = "body"
	body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var hue: Color = CARD_HUES[index % CARD_HUES.size()]
	if g["thumb"] != null:
		var tr := TextureRect.new()
		tr.texture = g["thumb"]
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(tr)
	else:  # 썸네일 없는 게임: 색 그라데이션 + 첫 글자
		UI.gradient(body, Rect2(Vector2.ZERO, size), [[0.0, hue.lightened(0.12)], [0.55, hue.darkened(0.55)], [1.0, Color(0.03, 0.035, 0.06)]], Vector2(0.1, 0), Vector2(0.9, 1))
		if size.y > 300:
			UI.text(body, str(g["name"]).substr(0, 1), int(size.y * 0.4), Vector2(size.x / 2, size.y * 0.06), Color(UI.WHITE, 0.92), false, 0, 0, false, 900)
			UI.rect(body, Rect2(size.x / 2 - 22, size.y * 0.56, 44, 2), Color(1, 1, 1, 0.5))
		else:
			UI.text(body, str(g["name"]).substr(0, 1), int(size.y * 0.48), Vector2(size.x - 24, size.y * 0.02), Color(UI.WHITE, 0.3), false, 0, 1, false, 900)
	UI.gradient(body, Rect2(Vector2.ZERO, size), [[0.0, Color(0.02, 0.025, 0.05, 0.35)], [0.22, Color(0.02, 0.025, 0.05, 0.0)], [0.5, Color(0.02, 0.025, 0.05, 0.0)], [0.9, Color(0.02, 0.025, 0.05, 0.94)]])
	UI.text(body, "%02d" % (index + 1), 20, Vector2(22, 18), Color(UI.WHITE, 0.85), true, 0, -1, false, 700)
	var big := size.y > 300
	var nl := UI.text(body, g["name"], 34 if big else 26, Vector2(22, size.y - (102 if big else 82)), UI.WHITE, false, 0, -1, false, 800)
	while nl.label_settings.font_size > 18 and nl.get_minimum_size().x > size.x - 44:
		nl.label_settings.font_size -= 1
	var tag := UI.text(body, g["tagline"], 18 if big else 16, Vector2(23, size.y - (50 if big else 42)), Color(UI.WHITE, 0.72), false, 0, -1, true)
	tag.size.x = size.x - 44
	tag.clip_text = true
	var veil := UI.rect(body, Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.03, 0.32))
	veil.name = "veil"

	UI.panel(card, Rect2(Vector2.ZERO, size), UI.outline(Color(1, 1, 1, 0.16), 16, 1))
	var selp := UI.panel(card, Rect2(Vector2.ZERO, size), UI.outline(Kit.GOLD, 16, 2))
	selp.name = "sel"
	var play := UI.panel(selp, Rect2(size.x - 80, 16, 64, 32), UI.flat(Kit.GOLD, 6))
	UI.text(play, "시작", 17, Vector2(32, 5), UI.INK, false, 0, 0, false, 800)

	card.mouse_entered.connect(func():
		if _state == "menu" and sel != index:
			sel = index
			Kit.sfx("move", -8.0)
			_refresh_menu())
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _state == "menu":
			sel = index
			_refresh_menu()
			_start_game())
	return card


func _move(step: int) -> void:
	if games.is_empty():
		return
	if absi(step) == 1:
		sel = posmod(sel + step, games.size())
	else:
		sel = clampi(sel + step, 0, games.size() - 1)
	Kit.sfx("move", -6.0)
	_refresh_menu()


func _key_menu(k: int) -> void:
	match k:
		KEY_LEFT: _move(-1)
		KEY_RIGHT: _move(1)
		KEY_UP: _move(-COLS)
		KEY_DOWN: _move(COLS)
		KEY_PAGEUP: _move(-PER_PAGE)
		KEY_PAGEDOWN: _move(PER_PAGE)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _start_game()
		KEY_ESCAPE: _goto("attract")
		KEY_F1: _goto("pin")


func _pick_index() -> int:
	var pick: String = _args.get("pick", "0")
	for i in games.size():
		if games[i]["id"] == pick:
			return i
	return clampi(int(pick), 0, maxi(0, games.size() - 1))


# ---------- 게임 실행 ----------

func _start_game() -> void:
	if _busy or _state != "menu" or games.is_empty():
		return
	_busy = true
	var g: Dictionary = games[sel]
	Kit.sfx("click")
	if pending.is_empty():  # 결과는 게임 시작 전에 확률표로 결정
		pending = _forced() if _forced() != "" else Store.draw()
	var prize := pending
	await _fade_to(1.0, 0.3)
	var node := _instantiate(g["path"])
	if node == null:
		_busy = false
		_fade_to(0.0, 0.3)
		_toast("게임에 문제가 생겼어요. 다른 게임을 골라주세요")
		return
	var r := Store.rank(prize)
	for kv in [["win", prize != Store.LOSE], ["prize", prize], ["rank", r]]:
		if kv[0] in node:
			node.set(kv[0], kv[1])
	_ui.visible = false
	remove_child(_back)  # 게임의 카메라/환경과 겹치지 않게
	_game = node
	_game_name = g["name"]
	_state = "game"
	_idle = 0.0
	node.connect("finished", _on_game_finished.bind(node))
	add_child(node)
	_busy = false
	_fade_to(0.0, 0.35)


func _instantiate(path: String) -> Node:
	var script = load(path)
	if not (script is Script) or not (script as Script).can_instantiate():
		push_warning("게임을 불러올 수 없음: " + path)
		return null
	var obj = (script as Script).new()
	if not (obj is Node) or not (obj as Node).has_signal("finished"):
		push_warning("게임 형식이 맞지 않음 (Node + finished 신호 필요): " + path)
		if obj is Node:
			(obj as Node).free()
		return null
	return obj


func _on_game_finished(completed, node: Node) -> void:
	if node == _game and _state == "game" and not _busy:
		_end_game.call_deferred(bool(completed))


func _end_game(completed: bool) -> void:
	if _busy or _state != "game":
		return
	_busy = true
	await _fade_to(1.0, 0.3)
	if is_instance_valid(_game):
		if _game.get_parent() == self:
			remove_child(_game)
		_game.queue_free()
	_game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # 게임이 바꿔놓았을 수 있는 것들을 되돌림
	Engine.time_scale = 1.0
	get_tree().paused = false
	add_child(_back)
	move_child(_back, 0)
	_back.cam.make_current()
	_ui.visible = true
	_busy = false
	if completed:
		last_prize = pending
		last_code = _record(_game_name, pending)
		pending = ""
		_goto("result")
	else:  # 중간에 나감: 뽑힌 경품은 다음 판에 그대로 (다시 뽑기 불가)
		_goto("menu")
	_fade_to(0.0, 0.4)


# ---------- 결과 ----------

func _build_result(scr: Control) -> void:
	var win := last_prize != Store.LOSE and last_prize != ""
	var rank := Store.rank(last_prize)
	var t: Dictionary = Kit.tier(rank)
	var c: Color = t["color"]
	_redeemed = false
	_ticket = null
	_set_hints([])
	_timeout = 60.0 if win else 9.0
	UI.rect(scr, Rect2(0, H - 4, W, 4), Color(1, 1, 1, 0.1))
	_bar = UI.rect(scr, Rect2(0, H - 4, W, 4), c if win else UI.GRAY)
	var hint := UI.text(scr, "아무 키나 누르거나 화면을 터치하면 처음으로", 17, Vector2(W / 2, 672), UI.GRAY, false, 0, 0, true)
	hint.modulate.a = 0.0
	hint.create_tween().tween_property(hint, "modulate:a", 1.0, 0.4).set_delay(RESULT_LOCK)
	if not win:
		_right.text = "결과"
		_set_dim(0.84)
		_back.set_mode(0.0, Color(0.4, 0.46, 0.7), 0.24)
		Kit.sfx("lose")
		var holder := Control.new()
		holder.position = Vector2(W / 2, 318)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scr.add_child(holder)
		UI.text(holder, "꽝", 230, Vector2(0, -150), UI.WHITE, false, 0, 0, false, 900)
		holder.scale = Vector2(0.94, 0.94)
		holder.create_tween().tween_property(holder, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		UI.text(scr, "아쉽지만 다음 기회에 만나요", 32, Vector2(W / 2, 486), UI.WHITE, false, 0, 0, false, 700)
		UI.text(scr, "오늘 축제, 즐겁게 보내세요", 20, Vector2(W / 2, 540), UI.GRAY, false, 0, 0, true)
		return

	_right.text = "당첨"
	_set_dim(0.62)
	_back.set_mode(0.0, c, 0.2)
	Kit.sfx("jackpot" if rank == Kit.TOP_TIER else "win")
	scr.add_child(Kit.confetti(Vector2(W, H), c, rank, 5.0, 2))  # 종이 꽃가루가 쿠폰 뒤로 천천히 내림

	UI.text(scr, "%s 등급 당첨" % t["kor"], 50, Vector2(W / 2, 102), UI.WHITE, false, 0, 0, false, 800)

	var tw_size := Vector2(940, 300)
	var split := 516.0
	var rest := Vector2(W / 2 - tw_size.x / 2, 208)
	_ticket = Control.new()
	_ticket.position = rest
	_ticket.size = tw_size
	_ticket.pivot_offset = tw_size / 2
	_ticket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_ticket)
	Kit.soft_shadow(_ticket, Rect2(10, 6, tw_size.x - 20, tw_size.y - 12), 12.0, 38.0, 0.62, Vector2(0, 22))  # 바닥에 닿은 그림자

	var paper := UI.rect(Kit.round_clip(_ticket, tw_size, 12.0), Rect2(Vector2.ZERO, tw_size), Kit.PAPER)  # 종이 한 장: 절취선 구멍이 실제로 뚫려 있음
	paper.material = Kit.paper_material(tw_size, 12.0, split, 13.0)
	var foil := UI.rect(paper, Rect2(0, 0, tw_size.x, 54), c)  # 등급 색 박 띠 (빛이 훑고 지나감)
	foil.material = Kit.foil_material(foil.size, true, 3.6, Vector3(split, 0.0, 13.0))
	UI.rect(paper, Rect2(0, 54, tw_size.x, 1), Color(UI.INK, 0.18))
	UI.text(paper, "%s 할인 쿠폰" % TITLE, 19, Vector2(36, 15), UI.INK, false, 0, -1, false, 800)
	UI.text(paper, "%s 등급" % t["kor"], 19, Vector2(tw_size.x - 36, 15), UI.INK, false, 0, 1, false, 800)

	var psize := 86
	while psize > 36 and UI.font(false, -int(round(psize * 0.025)), false, 900).get_string_size(last_prize, HORIZONTAL_ALIGNMENT_LEFT, -1, psize).x > split - 76:
		psize -= 2
	var pl := UI.text(paper, last_prize, psize, Vector2(34, 72), UI.INK, false, -int(round(psize * 0.025)), -1, false, 900)
	pl.size.y = 136
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.text(paper, "1회 사용  ·  스태프 확인 후 할인", 18, Vector2(37, 218), Color(UI.INK, 0.66), false, 0, -1, false, 600)
	var now := Time.get_datetime_dict_from_system()
	UI.text(paper, "No. %04d  ·  %04d.%02d.%02d %02d:%02d" % [_plays().size(), now["year"], now["month"], now["day"], now["hour"], now["minute"]],
		15, Vector2(37, 252), Color(UI.INK, 0.46), true, 0, -1, false, 500)

	var cx := (split + tw_size.x) / 2
	UI.text(paper, "쿠폰 코드", 17, Vector2(cx, 84), Color(UI.INK, 0.58), false, 0, 0, false, 700)
	var pitch := 53.0
	for i in last_code.length():  # 글자마다 같은 너비의 칸에, 세 글자씩 끊어서 — 멀리서도 또박또박 읽히게
		var x := cx + (i - (last_code.length() - 1) / 2.0) * pitch + (16.0 if i >= 3 else -16.0)
		UI.text(paper, last_code[i], 72, Vector2(x, 108), UI.INK, true, 1, 0, false, 800)
	UI.rect(paper, Rect2(cx - 150, 210, 300, 1), Color(UI.INK, 0.16))
	UI.text(paper, "스태프에게 보여주세요", 16, Vector2(cx, 226), Color(UI.INK, 0.58), false, 0, 0, false, 600)

	# 등장: 살짝 기운 채 내려앉아 자리를 잡고, 그 뒤로 아주 느리게 흔들림
	_ticket.position = rest + Vector2(0, 54)
	_ticket.scale = Vector2(0.9, 0.9)
	_ticket.rotation_degrees = -6.0
	_ticket.modulate.a = 0.0
	var tt := _ticket.create_tween().set_parallel()
	tt.tween_property(_ticket, "position", rest, 0.6).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(_ticket, "scale", Vector2.ONE, 0.6).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(_ticket, "rotation_degrees", -1.4, 0.8).set_delay(0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(_ticket, "modulate:a", 1.0, 0.25).set_delay(0.2)
	var ticket := _ticket
	tt.chain().tween_callback(func():
		var sway := ticket.create_tween().set_loops()
		sway.tween_property(ticket, "rotation_degrees", -0.9, 2.6).set_trans(Tween.TRANS_SINE)
		sway.tween_property(ticket, "rotation_degrees", -1.4, 2.6).set_trans(Tween.TRANS_SINE))

	var show := UI.text(scr, "스태프에게 이 화면을 보여주세요", 30, Vector2(W / 2, 562), UI.WHITE, false, 0, 0, false, 700)
	show.modulate.a = 0.0
	show.create_tween().tween_property(show, "modulate:a", 1.0, 0.4).set_delay(0.7)
	UI.text(scr, "스태프  F2  사용 처리", 14, Vector2(W - 56, 682), Color(UI.WHITE, 0.3), false, 0, 1, true)


func _key_result(k: int) -> void:
	if k == KEY_F2:
		if _ticket != null and not _redeemed:  # 스태프가 그 자리에서 사용 처리
			var res := _redeem(last_code)
			if res["status"] != "none":
				_redeemed = true
				_stamp()
	elif _t > RESULT_LOCK:
		_goto("attract")


const STAMP_SHADER := "
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
float h21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) { c.rgb /= c.a; }
	vec2 p = FRAGCOORD.xy;
	float n = vn(p * 0.07) * 0.55 + vn(p * 0.29) * 0.45;
	float ink = smoothstep(0.2, 0.5, n) * (0.84 + 0.16 * h21(floor(p)));
	COLOR *= c;
	COLOR.a *= mix(0.38, 0.94, ink);
}
"


func _stamp() -> void:  # 잉크 도장: 붉은 잉크가 고르지 않게 묻은 느낌
	Kit.sfx("coin")
	var ink := Color(0.8, 0.12, 0.1)
	var st := CanvasGroup.new()
	st.position = Vector2(352, 208)  # 왼쪽 칸 아래 — 쿠폰 코드는 가리지 않게
	st.rotation_degrees = -9.0
	var sh := Shader.new()
	sh.code = STAMP_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	st.material = mat
	_ticket.add_child(st)
	UI.panel(st, Rect2(-146, -54, 292, 108), UI.outline(ink, 12, 5))
	UI.panel(st, Rect2(-136, -44, 272, 88), UI.outline(ink, 6, 2))
	UI.text(st, "사용 완료", 50, Vector2(0, -42), ink, false, 2, 0, false, 900)
	var now := Time.get_datetime_dict_from_system()
	UI.text(st, "%02d.%02d  %02d:%02d" % [now["month"], now["day"], now["hour"], now["minute"]], 14, Vector2(0, 20), ink, true, 1, 0, false, 700)
	st.scale = Vector2(1.7, 1.7)
	st.modulate.a = 0.0
	var tw := st.create_tween().set_parallel()
	tw.tween_property(st, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(st, "modulate:a", 1.0, 0.1)
	var press := _ticket.create_tween()  # 쾅 찍히는 순간 쿠폰이 살짝 눌림
	press.tween_interval(0.16)
	press.tween_property(_ticket, "scale", Vector2(0.985, 0.985), 0.05)
	press.tween_property(_ticket, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------- 관리자: PIN ----------

func _build_pin(scr: Control) -> void:
	_right.text = "관리자"
	_set_dim(0.66)
	_back.set_mode(0.0, Backdrop.WARM, 0.22)
	_set_hints([["0–9", "입력"], ["Enter", "확인", _pin_submit], ["Esc", "취소", func(): _goto("attract")]])
	_pin_panel = UI.glass(scr, Rect2(W / 2 - 210, 104, 420, 536), 20, Color(Kit.GOLD, 0.6), 0.7)
	UI.text(_pin_panel, "관리자 PIN", 30, Vector2(210, 40), UI.WHITE, false, 0, 0, false, 800)
	UI.text(_pin_panel, "숫자를 입력하고 확인을 누르세요", 16, Vector2(210, 86), UI.GRAY, false, 0, 0, true)
	_pin_dots = Control.new()
	_pin_dots.position = Vector2(210, 150)
	_pin_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_panel.add_child(_pin_dots)
	_pin_dots.draw.connect(func():
		var slots := maxi(4, _typed.length())
		for i in slots:
			var x := (i - (slots - 1) / 2.0) * 38.0
			if i < _typed.length():
				_pin_dots.draw_circle(Vector2(x, 0), 10, Kit.GOLD)
			else:
				_pin_dots.draw_arc(Vector2(x, 0), 9, 0, TAU, 32, Color(1, 1, 1, 0.3), 2.0, true))
	var keys := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "지움", "0", "확인"]
	for i in keys.size():
		var key: String = keys[i]
		var r := Rect2(48 + (i % 3) * 112, 200 + (i / 3) * 76, 100, 64)
		var cb := func():
			if key == "지움":
				_typed = _typed.left(-1)
			elif key == "확인":
				_pin_submit()
				return
			elif _typed.length() < 8:
				_typed += key
			Kit.sfx("tick", -8.0)
			_pin_dots.queue_redraw()
		var b := UI.button(_pin_panel, r, key, 28 if key.length() == 1 else 19, true, cb)
		if key == "확인":
			b.add_theme_stylebox_override("normal", UI.flat(Color(Kit.GOLD, 0.16), 8, Color(Kit.GOLD, 0.7), 1))


func _pin_submit() -> void:
	if _state != "pin":
		return
	if _typed == _pin:
		Kit.sfx("click")
		_goto("admin")
		return
	_typed = ""
	_pin_dots.queue_redraw()
	Kit.sfx("error")
	var b: Panel = _pin_panel.get_meta("border")
	b.add_theme_stylebox_override("panel", UI.outline(UI.RED, 20, 2))
	var x0 := W / 2 - 210
	var tw := _pin_panel.create_tween()
	for i in 6:
		tw.tween_property(_pin_panel, "position:x", x0 + (10.0 if i % 2 == 0 else -10.0) * (1.0 - i / 6.0), 0.05)
	tw.tween_property(_pin_panel, "position:x", x0, 0.05)
	tw.tween_callback(func(): b.add_theme_stylebox_override("panel", UI.outline(Color(Kit.GOLD, 0.6), 20, 1)))


func _key_pin(k: int, e: InputEventKey) -> void:
	if k == KEY_ESCAPE:
		_goto("attract")
	elif k == KEY_BACKSPACE:
		_typed = _typed.left(-1)
	elif k in [KEY_ENTER, KEY_KP_ENTER]:
		_pin_submit()
		return
	else:
		var ch := _key_char(e)
		if ch != "" and ch.is_valid_int() and _typed.length() < 8:
			_typed += ch
			Kit.sfx("tick", -8.0)
	if is_instance_valid(_pin_dots):
		_pin_dots.queue_redraw()


# ---------- 관리자 ----------

func _build_admin(scr: Control) -> void:
	_right.text = "관리자"
	_set_dim(0.7)
	_back.set_mode(0.0, Backdrop.WARM, 0.22)
	_set_hints([["F5", "CSV 내보내기", _admin_export], ["F10", "프로그램 종료", func(): get_tree().quit()], ["F11", "전체화면", _toggle_fullscreen], ["Esc", "닫기", func(): _goto("attract")]])
	UI.text(scr, "관리자", 40, Vector2(56, 90), UI.WHITE, false, 0, -1, false, 800)
	if dry:
		UI.text(scr, "연습 모드  ·  기록 파일에 저장되지 않음", 16, Vector2(186, 112), UI.RED, false, 0, -1, false, 600)
	UI.glass(scr, Rect2(56, 158, 790, 300), 16)
	UI.glass(scr, Rect2(866, 158, 358, 300), 16)
	_admin_stats = Control.new()
	_admin_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_admin_stats)
	_admin_refresh()

	var box := UI.glass(scr, Rect2(56, 474, 1168, 180), 16, Color(Kit.GOLD, 0.55))
	UI.text(box, "쿠폰 사용 처리", 19, Vector2(24, 15), UI.WHITE)
	UI.panel(box, Rect2(24, 50, 300, 78), UI.flat(Color(0.01, 0.012, 0.025, 0.85), 10, Color(Kit.GOLD, 0.8), 1))
	_code_label = UI.text(box, "", 46, Vector2(174, 60), UI.WHITE, true, 4, 0, false, 800)
	_msg = UI.text(box, "쿠폰 코드를 입력하고 Enter", 18, Vector2(24, 141), UI.GRAY, false, 0, -1, true)
	for i in Store.ALPHABET.length():  # 터치/마우스용 글자판
		var ch: String = Store.ALPHABET[i]
		UI.button(box, Rect2(360 + (i % 16) * 49, 22 + (i / 16) * 50, 45, 44), ch, 21, true, func(): _admin_type(ch))
	UI.button(box, Rect2(360 + 12 * 49, 124, 94, 40), "지우기", 17, false, func(): _admin_type("<"))
	var ok := UI.button(box, Rect2(360 + 14 * 49, 124, 94, 40), "확인", 17, false, _admin_submit)
	ok.add_theme_stylebox_override("normal", UI.flat(Color(Kit.GOLD, 0.16), 8, Color(Kit.GOLD, 0.7), 1))
	_admin_type("")


func _admin_refresh() -> void:
	for c in _admin_stats.get_children():
		c.queue_free()
	var s := _admin_stats
	var plays := _plays()
	var total := plays.size()
	var tl := UI.text(s, str(total), 52, Vector2(W - 90, 82), UI.WHITE, true, 0, 1, false, 800)
	UI.text(s, "판", 22, Vector2(W - 82, 110), UI.GRAY)
	UI.text(s, "누적 플레이", 17, Vector2(W - 106 - tl.get_minimum_size().x, 115), UI.GRAY, false, 0, 1, false, 600)

	var cols := [[92.0, "경품", -1], [470.0, "목표", 1], [560.0, "실제", 1], [650.0, "나온 수", 1], [740.0, "사용 완료", 1], [826.0, "남은 수량", 1]]
	for c in cols:
		UI.text(s, c[1], 16, Vector2(c[0], 174), UI.GRAY, false, 0, c[2], false, 600)
	UI.rect(s, Rect2(76, 204, 750, 1), UI.LINE)
	for i in Store.PRIZES.size():
		var p: Dictionary = Store.PRIZES[i]
		var name: String = p["name"]
		var mine := plays.filter(func(x): return x.get("prize", "") == name)
		var n := mine.size()
		var used := mine.filter(func(x): return str(x.get("redeemed_at", "")) != "").size()
		var y := 214.0 + i * 47.0
		var lose := name == Store.LOSE
		UI.rect(s, Rect2(76, y + 9, 4, 24), UI.GRAY if lose else Kit.tier(Store.rank(name))["color"])
		UI.text(s, name, 22, Vector2(cols[0][0], y + 8), UI.WHITE)
		var vals := ["%s%%" % str(p["pct"]), ("%.1f%%" % (n * 100.0 / total)) if total > 0 else "-", str(n), "-" if lose else str(used),
			"-" if int(p["cap"]) < 0 else str(maxi(0, int(p["cap"]) - n))]
		for j in vals.size():
			UI.text(s, vals[j], 23, Vector2(cols[j + 1][0], y + 7), UI.WHITE if j != 1 else UI.GRAY, true, 0, 1, false, 700)
		if i < Store.PRIZES.size() - 1:
			UI.rect(s, Rect2(76, y + 44, 750, 1), Color(1, 1, 1, 0.06))

	UI.text(s, "게임별 플레이", 16, Vector2(886, 174), UI.GRAY, false, 0, -1, false, 600)
	UI.rect(s, Rect2(886, 204, 318, 1), UI.LINE)
	var per := {}
	for x in plays:
		var gname := str(x.get("game", "?"))
		per[gname] = int(per.get(gname, 0)) + 1
	var names := per.keys()
	names.sort_custom(func(a, b): return per[a] > per[b])
	if names.is_empty():
		UI.text(s, "아직 기록 없음", 20, Vector2(886, 222), UI.GRAY, false, 0, -1, true)
	var top := int(per[names[0]]) if not names.is_empty() else 1
	for i in mini(names.size(), 6):
		var y := 216.0 + i * 40.0
		if i == 5 and names.size() > 6:
			UI.text(s, "외 %d개 게임" % (names.size() - 5), 19, Vector2(886, y + 4), UI.GRAY, false, 0, -1, true)
			break
		UI.text(s, names[i], 20, Vector2(886, y + 3), UI.WHITE)
		UI.text(s, str(per[names[i]]), 22, Vector2(1204, y + 2), UI.WHITE, true, 0, 1, false, 700)
		UI.rect(s, Rect2(886, y + 33, 318, 2), Color(1, 1, 1, 0.07))
		UI.rect(s, Rect2(886, y + 33, 318.0 * int(per[names[i]]) / top, 2), Color(Kit.GOLD, 0.8))


func _admin_type(ch: String) -> void:
	if ch == "<":
		_typed = _typed.left(-1)
	elif ch != "" and _typed.length() < 6:
		_typed += ch
	if ch != "":
		Kit.sfx("tick", -8.0)
	_code_label.text = _typed if _typed != "" else "––––––"
	_code_label.label_settings.font_color = UI.WHITE if _typed != "" else Color(1, 1, 1, 0.16)


func _admin_submit() -> void:
	if _typed == "":
		return
	var code := _typed
	var res := _redeem(code)
	var at := str(res["at"]).replace("T", " ")
	match res["status"]:
		"ok": _admin_msg("%s 사용 처리 완료  —  %s" % [code, res["prize"]], UI.MINT)
		"used": _admin_msg("이미 사용된 쿠폰  %s  (%s)  —  %s" % [code, at, res["prize"]], UI.RED)
		_: _admin_msg("없는 코드  %s" % code, UI.RED)
	Kit.sfx("coin" if res["status"] == "ok" else "error")
	_typed = ""
	_admin_type("")
	_admin_refresh()


func _admin_msg(s: String, color: Color) -> void:
	_msg.text = s
	_msg.label_settings.font_color = color
	_msg.label_settings.font = UI.font(false, 0, false, 600)


func _admin_export() -> void:
	var path := _export_csv()
	if path == "":
		_admin_msg("CSV 를 저장하지 못했어요", UI.RED)
	else:
		_admin_msg("내보냄 (%d판):  %s" % [_plays().size(), path], UI.MINT)
		_msg.label_settings.font_size = 16


func _key_admin(k: int, e: InputEventKey) -> void:
	match k:
		KEY_ESCAPE: _goto("attract")
		KEY_F10: get_tree().quit()
		KEY_F5: _admin_export()
		KEY_BACKSPACE: _admin_type("<")
		KEY_ENTER, KEY_KP_ENTER: _admin_submit()
		_:
			var ch := _key_char(e)
			if ch != "":
				_admin_type(ch)


# ---------- 개발용: 입력 흉내 ----------

func _schedule_keys(spec: String) -> void:
	for item in spec.split(";", false):
		var kv := item.split(":", true, 1)
		if kv.size() == 2:
			get_tree().create_timer(float(kv[0])).timeout.connect(_fake_input.bind(kv[1]))


func _fake_input(tok: String) -> void:
	if tok.begins_with("result="):  # 결과 화면 미리보기 (등급 지정)
		last_prize = Store.prize_of_rank(clampi(int(tok.trim_prefix("result=")), 0, Kit.TOP_TIER))
		last_code = _record("미리보기", last_prize)
		_goto("result")
		return
	if tok.begins_with("click@"):
		var xy := tok.trim_prefix("click@").split(",")
		for pressed in [true, false]:
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT
			m.pressed = pressed
			m.position = Vector2(float(xy[0]), float(xy[1]))
			m.global_position = m.position
			_dispatch(m)
		return
	var code := OS.find_keycode_from_string(tok)
	var codes: Array = [code]
	if code == KEY_NONE or (tok.length() > 1 and tok.is_valid_int()):
		codes = []
		for ch in tok.to_upper():
			codes.append(ch.unicode_at(0))
	for c in codes:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = c
			ev.physical_keycode = c
			ev.pressed = pressed
			_dispatch(ev)


func _dispatch(ev: InputEvent) -> void:
	_faking = true
	get_viewport().push_input(ev)
	_faking = false
