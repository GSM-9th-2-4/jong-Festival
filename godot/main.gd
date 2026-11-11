extends Node
## 진입점. 지금은 펀치머신 장면만 띄움 (런처는 다음 단계).
## 개발용: `godot --path godot -- --shot=/경로/파일.png` → 잠깐 돌린 뒤 스크린샷 저장하고 종료.

func _ready() -> void:
	var scene: Node = load("res://games/punch/punch.gd").new()
	add_child(scene)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot(a.trim_prefix("--shot="))


func _shot(path: String) -> void:
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
