extends Node3D
## 골키퍼(모델 파일이 없을 때 쓰는 대신용): 캡슐/구로 만든 관절 인형. 자세(관절 각도 묶음)를 섞어서 움직임.
## +z(카메라 쪽)를 바라봄. 팔다리는 관절에서 -y 로 뻗음. L = +x 쪽, R = -x 쪽.

const HIP_Y := 0.95

var pelvis: Node3D
var joints := {}
var glove_l: Node3D
var glove_r: Node3D

var _side := 0        # -1 / 0 / +1
var _high := 0.5      # 0 낮게 ~ 1 높게
var _x0 := 0.0
var _keys := []       # [준비, 도약, 뻗기, 착지]


## style: 색을 바꿔 다른 선수(키커)로도 씀 — {"jersey": Color, "sock": Color, "glove": Color}
func build(style := {}) -> void:
	var jersey := Kit.pbr("cotton_jersey", Vector3(3, 3, 3), style.get("jersey", Color(0.95, 0.80, 0.10)), true)
	jersey.metallic = 0.0
	jersey.metallic_texture = null
	var shorts := Kit.plain(Color(0.035, 0.04, 0.055), 0.0, 0.7)
	var skin := Kit.plain(Color(0.74, 0.53, 0.42), 0.0, 0.55)
	var sock := Kit.plain(style.get("sock", Color(0.90, 0.76, 0.10)), 0.0, 0.8)
	var boot := Kit.plain(Color(0.03, 0.03, 0.03), 0.1, 0.35)
	var glove := Kit.plain(style.get("glove", Color(0.92, 0.93, 0.95)), 0.0, 0.6)
	var hair := Kit.plain(Color(0.05, 0.035, 0.03), 0.0, 0.8)

	pelvis = Node3D.new()
	add_child(pelvis)
	_part(pelvis, _capsule(0.125, 0.36), shorts, Vector3(0, 0.0, 0), Vector3(0, 0, 90), Vector3(1.0, 1.0, 0.85))

	var spine := _joint("spine", pelvis, Vector3(0, 0.06, 0))
	_part(spine, _capsule(0.155, 0.50), jersey, Vector3(0, 0.22, 0), Vector3.ZERO, Vector3(1.12, 1.0, 0.74))
	_part(spine, _capsule(0.105, 0.50), jersey, Vector3(0, 0.44, 0), Vector3(0, 0, 90), Vector3(1.0, 1.0, 0.9))  # 어깨
	var head := _joint("head", spine, Vector3(0, 0.52, 0))
	_part(head, _capsule(0.05, 0.14), skin, Vector3(0, 0.03, 0))
	_part(head, _sphere(0.105), skin, Vector3(0, 0.16, 0.005), Vector3.ZERO, Vector3(0.92, 1.1, 1.0))
	_part(head, _sphere(0.108), hair, Vector3(0, 0.205, -0.006), Vector3.ZERO, Vector3(0.96, 0.96, 1.0))

	for s in [1.0, -1.0]:
		var n := "L" if s > 0 else "R"
		var arm := _joint("arm" + n, spine, Vector3(s * 0.225, 0.44, 0))
		_part(arm, _capsule(0.058, 0.34), jersey, Vector3(0, -0.14, 0))
		var fore := _joint("fore" + n, arm, Vector3(0, -0.29, 0))
		_part(fore, _capsule(0.047, 0.30), jersey, Vector3(0, -0.12, 0))
		var g := Node3D.new()
		g.position = Vector3(0, -0.31, 0)
		fore.add_child(g)
		_part(g, _sphere(0.075), glove, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.3, 0.6))
		_part(g, _capsule(0.05, 0.12), glove, Vector3(0, 0.08, 0))
		if s > 0:
			glove_l = g
		else:
			glove_r = g

		var thigh := _joint("thigh" + n, pelvis, Vector3(s * 0.10, -0.03, 0))
		_part(thigh, _capsule(0.098, 0.30), shorts, Vector3(0, -0.11, 0))
		_part(thigh, _capsule(0.078, 0.44), skin, Vector3(0, -0.24, 0))
		var shin := _joint("shin" + n, thigh, Vector3(0, -0.45, 0))
		_part(shin, _capsule(0.060, 0.42), sock, Vector3(0, -0.20, 0))
		_part(shin, _capsule(0.05, 0.25), boot, Vector3(0, -0.43, 0.06), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.8))

	_keys = [_ready_pose(), _ready_pose(), _ready_pose(), _ready_pose()]
	apply(_keys[0])


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 20
	c.rings = 6
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 24
	s.rings = 12
	return s


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)


func _joint(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	joints[n] = j
	return j


# ---------- 자세 ----------

func _ready_pose() -> Dictionary:
	return {
		"pos": Vector3(0, 0.83, 0), "rot": Vector3(0, 0, 0),
		"spine": Vector3(22, 0, 0), "head": Vector3(-18, 0, 0),
		"armL": Vector3(-28, 0, 38), "armR": Vector3(-28, 0, -38),
		"foreL": Vector3(-60, 0, 0), "foreR": Vector3(-60, 0, 0),
		"thighL": Vector3(-42, 0, 12), "thighR": Vector3(-42, 0, -12),
		"shinL": Vector3(58, 0, 0), "shinR": Vector3(58, 0, 0),
	}


static func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = (a[k] as Vector3).lerp(b[k], t)
	return out


func apply(p: Dictionary) -> void:
	pelvis.position = p["pos"]
	pelvis.rotation_degrees = p["rot"]
	for k in joints:
		(joints[k] as Node3D).rotation_degrees = p[k]


func idle(t: float) -> void:
	var p := _ready_pose()
	var sw := sin(t * 2.6)
	p["pos"] += Vector3(0.32 * sw, 0.035 * absf(cos(t * 2.6)) + 0.015 * sin(t * 7.0), 0)
	p["rot"] = Vector3(0, 0, -5.0 * sw)
	p["armL"] += Vector3(0, 0, 8.0 * sin(t * 5.2))
	p["armR"] += Vector3(0, 0, -8.0 * sin(t * 5.2 + 0.6))
	p["thighL"] += Vector3(6.0 * sw, 0, 5.0 * sw)
	p["thighR"] += Vector3(-6.0 * sw, 0, 5.0 * sw)
	apply(p)


## 다이브 계획. side: -1 왼쪽(-x) / 0 가운데 / +1 오른쪽(+x), high: 0~1
func plan(side: int, high: float) -> void:
	_side = side
	_high = high
	_x0 = pelvis.position.x
	var start := {}
	for k in joints:
		start[k] = (joints[k] as Node3D).rotation_degrees
	start["pos"] = pelvis.position
	start["rot"] = pelvis.rotation_degrees
	var s := float(side)
	var push: Dictionary
	var reach: Dictionary
	var land: Dictionary
	if side == 0:
		if high > 0.5:  # 제자리 점프, 두 손 위로
			push = _ready_pose()
			push["pos"] = Vector3(_x0 * 0.5, 0.74, 0.05)
			push["armL"] = Vector3(-50, 0, 30)
			push["armR"] = Vector3(-50, 0, -30)
			reach = {
				"pos": Vector3(0, 1.02 + 0.22 * high, 0.15), "rot": Vector3(0, 0, 0),
				"spine": Vector3(2, 0, 0), "head": Vector3(-8, 0, 0),
				"armL": Vector3(-22, 0, 158), "armR": Vector3(-22, 0, -158),
				"foreL": Vector3(-12, 0, 0), "foreR": Vector3(-12, 0, 0),
				"thighL": Vector3(-8, 0, 6), "thighR": Vector3(-16, 0, -6),
				"shinL": Vector3(14, 0, 0), "shinR": Vector3(30, 0, 0),
			}
			land = _ready_pose()
			land["pos"] = Vector3(0, 0.80, 0.15)
			land["armL"] = Vector3(-30, 0, 60)
			land["armR"] = Vector3(-30, 0, -60)
		else:  # 낮게 웅크려 몸으로 막기
			push = _ready_pose()
			push["pos"] = Vector3(_x0 * 0.5, 0.78, 0.05)
			reach = {
				"pos": Vector3(0, 0.66, 0.12), "rot": Vector3(0, 0, 0),
				"spine": Vector3(34, 0, 0), "head": Vector3(-26, 0, 0),
				"armL": Vector3(-58, 0, 24), "armR": Vector3(-58, 0, -24),
				"foreL": Vector3(-48, 0, -14), "foreR": Vector3(-48, 0, 14),
				"thighL": Vector3(-62, 0, 16), "thighR": Vector3(-62, 0, -16),
				"shinL": Vector3(96, 0, 0), "shinR": Vector3(96, 0, 0),
			}
			land = reach.duplicate()
			land["pos"] = Vector3(0, 0.62, 0.12)
	else:
		var ang := lerpf(84.0, 52.0, high)
		var yy := lerpf(0.52, 1.30, high)
		var xx := lerpf(1.95, 1.55, high)
		# lead = 다이브 방향 쪽(아래로 가는) 팔다리, trail = 반대쪽
		var lead := "L" if side > 0 else "R"
		var trail := "R" if side > 0 else "L"
		push = {
			"pos": Vector3(_x0 + s * 0.40, 0.70, 0.08), "rot": Vector3(0, 0, -s * 24),
			"spine": Vector3(16, 0, -s * 6), "head": Vector3(-12, 0, -s * 8),
			"arm" + lead: Vector3(-40, 0, s * 85), "arm" + trail: Vector3(-45, 0, -s * 30),
			"fore" + lead: Vector3(-35, 0, 0), "fore" + trail: Vector3(-55, 0, 0),
			"thigh" + lead: Vector3(-55, 0, s * 26), "thigh" + trail: Vector3(-14, 0, -s * 4),
			"shin" + lead: Vector3(80, 0, 0), "shin" + trail: Vector3(24, 0, 0),
		}
		reach = {
			"pos": Vector3(s * xx, yy, 0.25), "rot": Vector3(0, 0, -s * ang),
			"spine": Vector3(4, 0, -s * 10), "head": Vector3(-6, 0, -s * 12),
			"arm" + lead: Vector3(-12, 0, s * 172), "arm" + trail: Vector3(-18, 0, -s * 158),
			"fore" + lead: Vector3(-6, 0, 0), "fore" + trail: Vector3(-10, 0, 0),
			"thigh" + lead: Vector3(-6, 0, s * 4), "thigh" + trail: Vector3(-34, 0, -s * 22),
			"shin" + lead: Vector3(12, 0, 0), "shin" + trail: Vector3(58, 0, 0),
		}
		land = {
			"pos": Vector3(s * (xx + 0.55), 0.25, 0.3), "rot": Vector3(0, 0, -s * 88),
			"spine": Vector3(10, 0, -s * 4), "head": Vector3(-10, 0, s * 14),
			"arm" + lead: Vector3(-25, 0, s * 150), "arm" + trail: Vector3(-55, 0, -s * 105),
			"fore" + lead: Vector3(-30, 0, 0), "fore" + trail: Vector3(-45, 0, 0),
			"thigh" + lead: Vector3(-14, 0, s * 2), "thigh" + trail: Vector3(-46, 0, -s * 10),
			"shin" + lead: Vector3(26, 0, 0), "shin" + trail: Vector3(70, 0, 0),
		}
	_keys = [start, push, reach, land]


## k: 0(차는 순간) → 1(공이 도착, 최대로 뻗음),  l: 0 → 1 (착지)
func dive(k: float, l: float) -> void:
	var p: Dictionary
	if l <= 0.0:
		if k < 0.34:
			p = _blend(_keys[0], _keys[1], smoothstep(0.0, 1.0, k / 0.34))
		else:
			var u := (k - 0.34) / 0.66
			p = _blend(_keys[1], _keys[2], 1.0 - pow(1.0 - u, 1.7))
			# 몸은 포물선으로 뜸
			p["pos"] = (p["pos"] as Vector3) + Vector3(0, 0.10 * sin(u * PI) * (1.0 if _side != 0 else 0.3), 0)
	else:
		p = _blend(_keys[2], _keys[3], smoothstep(0.0, 1.0, l))
		var pos: Vector3 = p["pos"]
		pos.y = lerpf(_keys[2]["pos"].y, _keys[3]["pos"].y, minf(l * l * 1.6, 1.0))
		if l > 0.62:  # 착지 후 살짝 튕김
			pos.y += 0.04 * sin((l - 0.62) / 0.38 * PI)
		p["pos"] = pos
	apply(p)


func hands() -> Vector3:  ## 두 장갑의 가운데 (월드 좌표)
	return (glove_l.global_position + glove_r.global_position) * 0.5


func reach_point() -> Vector3:  ## 최대로 뻗었을 때 손 위치 (현재 자세는 유지)
	var keep := {}
	for k in joints:
		keep[k] = (joints[k] as Node3D).rotation_degrees
	keep["pos"] = pelvis.position
	keep["rot"] = pelvis.rotation_degrees
	dive(1.0, 0.0)
	var h := hands()
	apply(keep)
	return h


func land_time() -> float:
	return 0.55 if _side != 0 else 0.45
