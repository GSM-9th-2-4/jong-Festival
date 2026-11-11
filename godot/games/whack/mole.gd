extends Node3D
## 두더지 한 마리 (코드로 만든 3D 캐릭터). 원점 = 다 올라왔을 때 흙더미 테두리 높이, 얼굴은 +Z.
## kind: -1 보통, 0 꽝(회색·메롱·팻말), 1 레어, 2 에픽, 3 전설(황금+왕관), 4 크리티컬(빨강+왕관+반짝)

const HEAD := Vector3(0, 0.15, 0)
const HEAD_R := 0.1

var kind := -1
var fur: StandardMaterial3D
var _eyes: Node3D
var _eyes_hit: Node3D
var _mouth_hit: Node3D
var _teeth: Node3D
var _glow: Array[StandardMaterial3D] = []
var _hue := 0.0


## 옆모습 곡선(반지름 x, 높이 y)을 돌려서 만든 회전체. 위→아래 또는 아래→위 아무 순서나 가능.
static func lathe(profile: PackedVector2Array, segs := 40) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	for j in n:
		var a := profile[maxi(j - 1, 0)]
		var b := profile[mini(j + 1, n - 1)]
		var t := (b - a).normalized()
		var nr := Vector2(t.y, -t.x)  # 바깥쪽 법선 (곡선이 아래→위일 때)
		for i in segs + 1:
			var ang := TAU * i / segs
			var c := cos(ang)
			var s := sin(ang)
			st.set_normal(Vector3(nr.x * c, nr.y, nr.x * s))
			st.set_uv(Vector2(float(i) / segs, float(j) / n))
			st.add_vertex(Vector3(profile[j].x * c, profile[j].y, profile[j].x * s))
	for j in n - 1:
		for i in segs:
			var p := j * (segs + 1) + i
			st.add_index(p)
			st.add_index(p + 1)
			st.add_index(p + segs + 1)
			st.add_index(p + 1)
			st.add_index(p + segs + 2)
			st.add_index(p + segs + 1)
	return st.commit()


static func ball(parent: Node3D, r: float, pos: Vector3, mat: Material, sc := Vector3.ONE, seg := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = maxi(seg / 2, 3)
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = sc
	parent.add_child(mi)
	return mi


static func rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, r_top := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if r_top < 0.0 else r_top
	m.height = a.distance_to(b)
	m.radial_segments = 10
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.basis = Basis(x, y, x.cross(y))
	return mi


static func _on_head(az: float, el: float, r := HEAD_R) -> Vector3:
	az = deg_to_rad(az)
	el = deg_to_rad(el)
	return HEAD + r * Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))


static func fur_material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = Kit.pbr("polar_fleece", Vector3(7, 7, 7), color, true)
	m.albedo_texture = null  # 무늬(노멀/거칠기)만 쓰고 색은 직접
	m.metallic = 0.0
	m.metallic_texture = null
	m.roughness = 1.0
	m.normal_scale = 2.2
	m.rim_enabled = true  # 벨벳 같은 가장자리 빛
	m.rim = 0.55
	m.rim_tint = 0.6
	m.metallic_specular = 0.2
	return m


func build(k: int) -> void:
	kind = k
	var body_c := Color(0.24, 0.155, 0.105)
	var belly_c := Color(0.62, 0.47, 0.36)
	if kind == 0:
		body_c = Color(0.3, 0.31, 0.36)
		belly_c = Color(0.56, 0.57, 0.63)
	elif kind >= 1:
		var tc: Color = Kit.tier(kind)["color"]
		body_c = Color.from_hsv(tc.h, minf(tc.s * 1.25, 0.9), tc.v * (0.5 if kind != 3 else 1.0))
		belly_c = tc.lerp(Color.WHITE, 0.55) * 0.85
	fur = fur_material(body_c)
	if kind == 3:  # 황금: 금속
		fur.albedo_color = Color(1.0, 0.74, 0.3)
		fur.metallic = 1.0
		fur.roughness = 0.3
		fur.roughness_texture = null
		fur.normal_scale = 0.35
		fur.rim = 0.2
		belly_c = Color(1.0, 0.86, 0.52)
	elif kind >= 1:
		fur.emission_enabled = true
		fur.emission = body_c
		fur.emission_energy_multiplier = 0.06 if kind < 4 else 0.2
		_glow.append(fur)
	var belly := fur_material(belly_c)
	if kind == 3:
		belly.metallic = 1.0
		belly.roughness = 0.38
		belly.roughness_texture = null
		belly.normal_scale = 0.35
	var skin := Kit.plain(Color(0.93, 0.6, 0.58), 0.0, 0.45)
	skin.subsurf_scatter_enabled = true
	skin.subsurf_scatter_strength = 0.4
	var nose_m := Kit.plain(Color(0.9, 0.36, 0.42), 0.0, 0.18)
	nose_m.clearcoat_enabled = true
	var eye_m := Kit.plain(Color(0.015, 0.012, 0.012), 0.0, 0.04)
	eye_m.clearcoat_enabled = true
	eye_m.clearcoat_roughness = 0.02
	var white := Kit.plain(Color(0.96, 0.95, 0.9), 0.0, 0.25)
	var dark := Kit.plain(Color(0.16, 0.04, 0.05), 0.0, 0.6)
	var spark := Kit.emissive(Color.WHITE, 2.5)
	if kind == 3:
		skin = Kit.plain(Color(1.0, 0.8, 0.45), 1.0, 0.25)

	# 몸통 (달걀꼴 회전체)
	var prof := PackedVector2Array([Vector2(0.112, -0.26), Vector2(0.115, -0.05), Vector2(0.113, 0.04), Vector2(0.108, 0.1)])
	for d in range(90, -1, -9):
		var th := deg_to_rad(float(d))
		prof.append(Vector2(HEAD_R * sin(th) + 0.0001, HEAD.y + HEAD_R * 0.97 * cos(th)))
	var body := MeshInstance3D.new()
	body.mesh = lathe(prof, 40)
	body.material_override = fur
	add_child(body)

	# 배
	ball(self, 0.085, Vector3(0, 0.0, 0.052), belly, Vector3(0.82, 1.25, 0.8))
	# 주둥이 + 코
	var mz := _on_head(0, 14, 0.078)
	ball(self, 0.047, mz, belly, Vector3(1.2, 0.86, 1.0))
	ball(self, 0.02, mz + Vector3(0, 0.014, 0.043), nose_m, Vector3(1.25, 0.9, 0.9))
	ball(self, 0.005, mz + Vector3(0.006, 0.026, 0.052), spark, Vector3.ONE, 8)
	# 볼
	var cheek := Kit.plain(body_c.lerp(Color(1.0, 0.45, 0.5), 0.45), 0.0, 0.9)
	if kind != 3:
		for sx in [-1.0, 1.0]:
			ball(self, 0.02, _on_head(42 * sx, 12, 0.094), cheek, Vector3(1, 0.8, 0.5))
	# 귀
	for sx in [-1.0, 1.0]:
		var ep := _on_head(68 * sx, 52, 0.098)
		ball(self, 0.024, ep, fur, Vector3(1, 1, 0.7))
		ball(self, 0.014, ep + Vector3(0, 0.002, 0.012), skin, Vector3(1, 1, 0.5))
	# 수염
	var wh := Kit.plain(Color(0.9, 0.86, 0.8), 0.0, 0.4)
	for sx in [-1.0, 1.0]:
		for j in 3:
			var a := mz + Vector3(0.04 * sx, -0.004 + 0.007 * j, 0.022)
			rod(self, a, a + Vector3(0.062 * sx, -0.012 + 0.012 * j, 0.012), 0.0011, wh, 0.0003)

	# 눈 (보통) / 눈 (맞았을 때 > <)
	_eyes = Node3D.new()
	add_child(_eyes)
	_eyes_hit = Node3D.new()
	_eyes_hit.visible = false
	add_child(_eyes_hit)
	for sx in [-1.0, 1.0]:
		var e := _on_head(25 * sx, 40, 0.094)
		ball(_eyes, 0.0175, e, eye_m, Vector3(1, 1.12, 1))
		ball(_eyes, 0.0052, e + Vector3(0.004, 0.011, 0.011), spark, Vector3.ONE, 8)
		ball(_eyes, 0.0026, e + Vector3(-0.006, 0.002, 0.015), spark, Vector3.ONE, 8)
		if kind == 0:  # 시큰둥한 눈꺼풀
			ball(_eyes, 0.0195, e + Vector3(0, 0.0085, 0.001), fur, Vector3(1.05, 0.8, 1.0))
		var c := _on_head(25 * sx, 40, 0.103)
		var up := Vector3(0, 0.017, -0.012)
		var side := Vector3(0.017 * sx, 0, 0.004)
		rod(_eyes_hit, c - side, c + side * 0.9 + up, 0.0042, eye_m)
		rod(_eyes_hit, c - side, c + side * 0.9 - up, 0.0042, eye_m)

	# 입: 앞니 / 맞았을 때 벌린 입
	_teeth = Node3D.new()
	add_child(_teeth)
	_mouth_hit = Node3D.new()
	_mouth_hit.visible = false
	add_child(_mouth_hit)
	if kind == 0:  # 메롱
		var tongue := Kit.plain(Color(0.95, 0.42, 0.5), 0.0, 0.3)
		ball(_teeth, 0.016, mz + Vector3(0, -0.03, 0.036), tongue, Vector3(1.0, 1.5, 0.45))
		ball(_teeth, 0.012, mz + Vector3(0, -0.02, 0.03), dark, Vector3(1.6, 0.6, 0.8))
	else:
		for sx in [-1.0, 1.0]:
			var tooth := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.012, 0.017, 0.006)
			tooth.mesh = bm
			tooth.material_override = white
			tooth.position = mz + Vector3(0.0066 * sx, -0.034, 0.034)
			tooth.rotation.x = 0.25
			_teeth.add_child(tooth)
	ball(_mouth_hit, 0.017, mz + Vector3(0, -0.03, 0.03), dark, Vector3(1.0, 1.2, 0.8))

	# 팔 + 앞발 (구멍 가장자리를 짚음)
	for sx in [-1.0, 1.0]:
		var sh := Vector3(0.085 * sx, 0.07, 0.04)
		var paw := Vector3(0.078 * sx, 0.022, 0.108)
		if kind == 0:
			paw = Vector3(0.07 * sx, 0.05, 0.118)
		rod(self, sh, paw, 0.026, fur, 0.02)
		ball(self, 0.026, sh, fur)
		ball(self, 0.027, paw, skin, Vector3(1.1, 0.6, 1.2))
		for j in 3:
			var cp := paw + Vector3((j - 1) * 0.014, -0.002, 0.028)
			rod(self, cp, cp + Vector3((j - 1) * 0.004, -0.008, 0.02), 0.0045, white, 0.0008)

	if kind == 0:
		_sign()
	elif kind >= 3:
		_crown()
	elif kind >= 1:
		var g := Kit.emissive((Kit.tier(kind)["color"] as Color).lerp(Color.WHITE, 0.2), 2.2)
		g.roughness = 0.1
		g.metallic = 0.3
		_glow.append(g)
		var gem := ball(self, 0.02, _on_head(0, 68, 0.1), g, Vector3(1, 0.6, 1), 6)
		gem.rotation = Vector3(-0.5, 0.3, 0)
		if kind == 2:
			for sx in [-1.0, 1.0]:
				ball(self, 0.011, _on_head(22 * sx, 72, 0.1), g, Vector3(1, 0.6, 1), 5)


func _sign() -> void:  # "꽝" 팻말
	var wood: StandardMaterial3D = Kit.pbr("wood_planks", Vector3(3, 3, 3), Color(1.0, 0.95, 0.85), true)
	wood.metallic = 0.0
	var holder := Node3D.new()
	holder.position = Vector3(0, 0.062, 0.128)
	holder.rotation.x = -0.5
	add_child(holder)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.17, 0.105, 0.012)
	board.mesh = bm
	board.material_override = wood
	holder.add_child(board)
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.148, 0.085, 0.002)
	paper.mesh = pm
	paper.material_override = Kit.plain(Color(0.95, 0.93, 0.86), 0.0, 0.8)
	paper.position.z = 0.0065
	holder.add_child(paper)
	var lab := Label3D.new()
	lab.text = "꽝"
	lab.font = Kit.font_kr()
	lab.font_size = 160
	lab.pixel_size = 0.00048
	lab.modulate = Color(0.82, 0.1, 0.12)
	lab.outline_size = 0
	lab.shaded = true
	lab.position.z = 0.0082
	holder.add_child(lab)


func _crown() -> void:
	var gold := Kit.plain(Color(1.0, 0.78, 0.3), 1.0, 0.22)
	var holder := Node3D.new()
	holder.position = HEAD + Vector3(0, 0.086, -0.012)
	holder.rotation.x = -0.16
	add_child(holder)
	var band := MeshInstance3D.new()
	band.mesh = lathe(PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.054, 0.004), Vector2(0.054, 0.012), Vector2(0.05, 0.016),
		Vector2(0.052, 0.03), Vector2(0.046, 0.03), Vector2(0.044, 0.0), Vector2(0.05, 0.0)]), 32)
	band.material_override = gold
	holder.add_child(band)
	var gems := [Color(1.0, 0.1, 0.2), Color(0.2, 0.6, 1.0), Color(0.3, 1.0, 0.45)]
	for i in 6:
		var a := TAU * i / 6.0 + PI / 2.0
		var p := Vector3(cos(a) * 0.049, 0.028, sin(a) * 0.049)
		rod(holder, p, p + Vector3(cos(a) * 0.012, 0.042, sin(a) * 0.012), 0.014, gold, 0.002)
		ball(holder, 0.0065, p + Vector3(cos(a) * 0.013, 0.046, sin(a) * 0.013), gold)
		var gm := Kit.emissive(gems[i % 3], 1.6 if kind == 3 else 3.0)
		gm.roughness = 0.08
		ball(holder, 0.0075, Vector3(cos(a + 0.52) * 0.054, 0.009, sin(a + 0.52) * 0.054), gm, Vector3.ONE, 6)
	var velvet := fur_material(Color(0.5, 0.03, 0.08))
	ball(holder, 0.046, Vector3(0, 0.02, 0), velvet, Vector3(1, 0.75, 1))


func set_hit(on: bool) -> void:
	_eyes.visible = not on
	_eyes_hit.visible = on
	_teeth.visible = not on
	_mouth_hit.visible = on


func _process(dt: float) -> void:
	if kind == 4 and visible:  # 크리티컬: 무지갯빛으로 일렁임
		_hue = fmod(_hue + dt * 0.35, 1.0)
		var c := Color.from_hsv(_hue, 0.85, 1.0)
		fur.emission = c
		fur.emission_energy_multiplier = 0.07
		fur.albedo_color = Color.from_hsv(fmod(_hue + 0.97, 1.0), 0.9, 0.42)
