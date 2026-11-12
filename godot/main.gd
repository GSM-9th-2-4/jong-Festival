extends Node
## 진입점.
##   평소: 런처(res://core/launcher.gd) 실행. 런처가 아직 없으면 첫 게임을 바로 실행.
##   개발/테스트: godot --path godot -- --game=punch --rank=3 --auto --shots=shots/punch --at=1,4,9
##     --game=<폴더명>  그 게임만 실행      --rank=<0~4>  등급 지정 (0 = 꽝)
##     --auto           자동 플레이 (Kit.auto = true)
##     --shots=<폴더>   --at 의 각 시각(초)에 스크린샷 저장 (godot/ 기준 상대경로 가능). 게임이 끝나면 종료.
##     --input=<목록>   정해진 시각(초)에 진짜 입력 이벤트를 넣음 (자동 플레이 없이 조작 경로 확인용)
##                      예: --input="2:click@640,400;4:key=space;6:key=escape"   (좌표는 1280x720 기준)
##     --quit           게임이 끝나면 종료

var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Kit.auto = _args.has("auto")
	if _args.has("game"):
		_run_single(_args["game"], int(_args.get("rank", "1")))
	elif ResourceLoader.exists("res://core/launcher.gd"):
		add_child(load("res://core/launcher.gd").new())
	else:
		_run_single("punch", 1)
	if _args.has("shots"):
		_shots(_args["shots"], _args.get("at", "2"))
	if _args.has("input"):
		_inputs(_args["input"])


func _run_single(id: String, rank: int) -> void:
	var game: Node = load("res://games/%s/game.gd" % id).new()
	game.rank = clampi(rank, 0, Kit.TOP_TIER)
	game.win = rank > 0
	game.prize = Store.prize_of_rank(rank)
	game.finished.connect(func(completed: bool):
		print("finished: ", completed)
		if _args.has("shots") or _args.has("quit"):
			await get_tree().create_timer(0.3).timeout
			get_tree().quit())
	add_child(game)


func _shots(dir: String, at: String) -> void:
	if dir.is_relative_path():
		dir = ProjectSettings.globalize_path("res://").path_join(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var t0 := Time.get_ticks_msec()
	for s in at.split(","):
		var wait := float(s) - (Time.get_ticks_msec() - t0) / 1000.0
		if wait > 0:
			await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir.path_join("%05.1fs.png" % float(s)))
	if not _args.has("game"):
		get_tree().quit()


func _inputs(spec: String) -> void:
	var t0 := Time.get_ticks_msec()
	for item in spec.split(";", false):
		var parts := item.split(":", true, 1)
		var wait := float(parts[0]) - (Time.get_ticks_msec() - t0) / 1000.0
		if wait > 0:
			await get_tree().create_timer(wait).timeout
		var what := parts[1]
		for pressed in [true, false]:
			var ev: InputEvent
			if what.begins_with("click@"):
				var xy := what.trim_prefix("click@").split(",")
				var size := get_viewport().get_visible_rect().size
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.position = Vector2(float(xy[0]) / 1280.0 * size.x, float(xy[1]) / 720.0 * size.y)
				mb.global_position = mb.position
				mb.pressed = pressed
				ev = mb
			else:
				var k := InputEventKey.new()
				k.keycode = OS.find_keycode_from_string(what.trim_prefix("key=").capitalize())
				k.physical_keycode = k.keycode
				k.pressed = pressed
				ev = k
			Input.parse_input_event(ev)
			await get_tree().process_frame
		print("input: ", what)
