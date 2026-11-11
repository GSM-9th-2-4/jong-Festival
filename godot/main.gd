extends Node
## 진입점.
##   평소: 런처(res://core/launcher.gd) 실행. 런처가 아직 없으면 첫 게임을 바로 실행.
##   개발/테스트: godot --path godot -- --game=punch --rank=3 --auto --shots=shots/punch --at=1,4,9
##     --game=<폴더명>  그 게임만 실행      --rank=<0~4>  등급 지정 (0 = 꽝)
##     --auto           자동 플레이 (Kit.auto = true)
##     --shots=<폴더>   --at 의 각 시각(초)에 스크린샷 저장 (godot/ 기준 상대경로 가능). 게임이 끝나면 종료.

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
