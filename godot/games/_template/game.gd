extends Node3D
## 게임 템플릿. 복사해서 games/<내게임>/game.gd 로 저장 ('_' 로 시작하는 폴더는 메뉴에 안 뜸).
##
## 규칙
## - 파일 위치: res://games/<id>/game.gd  (그 게임에 필요한 것은 전부 그 폴더 안에)
## - NAME / TAGLINE 상수, finished 신호, win / prize / rank 변수는 아래 그대로 둘 것
## - 런처가 win/prize/rank 를 채운 뒤 add_child 함 → _ready 에서 장면 만들기
## - 결과(당첨/꽝, 등급)는 이미 정해져 있음. 게임은 그 결과대로 '연출'만. 끝나면 finished.emit(true)
## - ESC = finished.emit(false) (경품 없음).  마우스 클릭/터치/스페이스만으로 끝까지 갈 수 있어야 함
## - Kit.auto 가 true 면(자동 테스트) 약 1초 뒤 스스로 입력한 것처럼 진행할 것
## - 당첨 순간: `await get_tree().create_timer(Kit.celebrate(rank, prize)).timeout` → 등급 배너 + 폭죽
## - 추첨/쿠폰 기록 금지 (Store.draw / Store.record 호출 금지). Store.rank / Store.PRIZES 읽기만 가능
## - 소재: games/<id>/assets.json 에 Poly Haven 이름을 적고 `python3 godot/tools/fetch_assets.py`

const NAME := "템플릿"
const TAGLINE := "스페이스 한 번!"

signal finished(completed: bool)

var win := false      ## 당첨 여부
var prize := ""       ## 경품 이름 (예: "1,000원 할인", 꽝이면 "꽝")
var rank := 0         ## 등급 0(꽝)~4(크리티컬)

var _busy := false
var _ball: MeshInstance3D


func _ready() -> void:
	add_child(Kit.environment("studio_small_03", {"fog": 0.0}))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	ground.material_override = Kit.pbr("concrete_floor", Vector3(8, 8, 1))
	add_child(ground)

	_ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	_ball.mesh = sphere
	_ball.material_override = Kit.pbr("leather_red_02", Vector3(2, 1, 1))
	_ball.position = Vector3(0, 0.5, 0)
	add_child(_ball)

	var cam := Camera3D.new()
	cam.position = Vector3(1.6, 1.4, 3.2)
	cam.fov = 45
	add_child(cam)
	cam.look_at(Vector3(0, 0.6, 0))

	if Kit.auto:
		get_tree().create_timer(1.0).timeout.connect(_go)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		finished.emit(false)
	elif event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed):
		_go()


func _go() -> void:
	if _busy:
		return
	_busy = true
	Kit.sfx("kick")
	var tw := create_tween()
	tw.tween_property(_ball, "position:y", 2.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_ball, "position:y", 0.5, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tw.finished
	if win:
		await get_tree().create_timer(Kit.celebrate(rank, prize)).timeout
	else:
		Kit.sfx("groan")
		await get_tree().create_timer(1.5).timeout
	finished.emit(true)
