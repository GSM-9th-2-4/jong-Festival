extends Node3D
## 런처 뒤에 깔리는 3D 무대. 어두운 전시장 바닥 위에서 금색 고리가 천천히 돌고, 카메라가 그 둘레를 돈다.
## 게임이 도는 동안에는 런처가 이 노드를 트리에서 빼 둠 (게임의 카메라/환경과 겹치지 않게).

var cam: Camera3D
var _pivots: Array = []
var _core_light: OmniLight3D
var _core_mat: StandardMaterial3D
var _angle := 0.6
var _tw: Tween
var _tw2: Tween

const WARM := Color(1.0, 0.72, 0.36)
const R_PILLAR := 10.5


func _ready() -> void:
	var we := Kit.environment("studio_small_03", {"sky_energy": 0.55, "ambient": 0.3, "show_sky": false, "glow": 0.35, "exposure": 1.0})
	we.environment.fog_enabled = true  # 먼 바닥이 어둠 속으로 사라지게
	we.environment.fog_light_color = Color(0.012, 0.014, 0.03)
	we.environment.fog_density = 0.045
	we.environment.fog_sky_affect = 0.0
	add_child(we)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	floor_mesh.mesh = plane
	var fm := Kit.pbr("concrete_floor", Vector3(26, 26, 1), Color(0.1, 0.105, 0.125))
	fm.roughness = 0.32
	fm.metallic = 0.35
	fm.metallic_texture = null
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	# 받침대
	var base := _mesh(_cyl(1.25, 1.35, 0.34), Kit.pbr("metal_plate", Vector3(5, 0.4, 1), Color(0.3, 0.31, 0.36)), Vector3(0, 0.17, 0))
	base.name = "base"
	_mesh(_cyl(0.95, 1.0, 0.16), Kit.plain(Color(0.05, 0.05, 0.06), 0.9, 0.25), Vector3(0, 0.42, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = 1.0
	rim.outer_radius = 1.03
	_mesh(rim, Kit.emissive(WARM, 1.6), Vector3(0, 0.5, 0))

	# 주인공: 빛나는 구슬 + 서로 다른 축으로 도는 금 고리 3개
	var core := SphereMesh.new()
	core.radius = 0.3
	core.height = 0.6
	_core_mat = Kit.emissive(WARM, 1.7)
	_mesh(core, _core_mat, Vector3(0, 2.0, 0))
	_core_light = OmniLight3D.new()
	_core_light.position = Vector3(0, 2.0, 0)
	_core_light.light_color = WARM
	_core_light.light_energy = 2.2
	_core_light.omni_range = 9.0
	add_child(_core_light)
	var gold := Kit.plain(Color(1.0, 0.74, 0.3), 1.0, 0.2)
	var radii := [[0.58, 0.66], [0.84, 0.91], [1.1, 1.16]]
	var tilts := [Vector3(70, 0, 20), Vector3(25, 0, 75), Vector3(95, 40, 0)]
	for i in 3:
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 2.0, 0)
		pivot.rotation_degrees = tilts[i]
		add_child(pivot)
		var t := TorusMesh.new()
		t.inner_radius = radii[i][0]
		t.outer_radius = radii[i][1]
		t.rings = 96
		t.ring_segments = 24
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = gold
		pivot.add_child(mi)
		_pivots.append(pivot)

	# 등급 색 빛기둥 4개
	for i in 8:
		var a := deg_to_rad(22.5 + 45.0 * i)
		var c: Color = Kit.TIERS[i % 4 + 1]["color"]
		var holder := Node3D.new()
		holder.position = Vector3(cos(a) * R_PILLAR, 0, sin(a) * R_PILLAR)
		add_child(holder)
		holder.look_at(Vector3(0, 0, 0))
		var slab := BoxMesh.new()
		slab.size = Vector3(1.1, 5.0, 0.16)
		var sm := MeshInstance3D.new()
		sm.mesh = slab
		sm.position.y = 2.5
		sm.material_override = Kit.plain(Color(0.03, 0.03, 0.04), 0.9, 0.22)
		holder.add_child(sm)
		for side in [-1.0, 1.0]:
			var strip := BoxMesh.new()
			strip.size = Vector3(0.03, 5.0, 0.18)
			var st := MeshInstance3D.new()
			st.mesh = strip
			st.position = Vector3(0.57 * side, 2.5, 0)
			st.material_override = Kit.emissive(c, 1.5)
			holder.add_child(st)
		var l := OmniLight3D.new()
		l.position = Vector3(0, 1.4, -1.2)
		l.light_color = c
		l.light_energy = 2.2
		l.omni_range = 6.5
		holder.add_child(l)

	# 앞쪽에 흩어진 공 (초점 밖에서 흐려져 깊이감을 줌)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var mats := [
		Kit.pbr("leather_red_02", Vector3(2, 1, 1)),
		Kit.plain(Color(0.92, 0.93, 0.96), 1.0, 0.07),
		gold,
		Kit.pbr("rubber_tiles", Vector3(3, 2, 1), Color(0.5, 0.5, 0.55)),
		Kit.plain(Color(0.04, 0.04, 0.05), 0.2, 0.08),
	]
	for i in 11:
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.4, 4.3)
		var r := rng.randf_range(0.16, 0.42)
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 48
		s.rings = 24
		_mesh(s, mats[i % mats.size()], Vector3(cos(a) * d, r, sin(a) * d))

	var key := SpotLight3D.new()
	key.position = Vector3(1.5, 8.5, 1.0)
	key.light_energy = 14.0
	key.spot_range = 16.0
	key.spot_angle = 34.0
	key.spot_attenuation = 1.4
	key.shadow_enabled = true
	key.light_color = Color(1.0, 0.95, 0.88)
	add_child(key)
	key.look_at(Vector3(0, 0.5, 0))

	cam = Camera3D.new()
	cam.fov = 36.0
	cam.h_offset = -1.75
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 10.0
	attr.dof_blur_far_transition = 8.0
	attr.dof_blur_near_enabled = true
	attr.dof_blur_near_distance = 4.2
	attr.dof_blur_near_transition = 2.0
	attr.dof_blur_amount = 0.09
	cam.attributes = attr
	add_child(cam)
	_place_cam()


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 96
	return c


func _place_cam() -> void:
	var y := 2.05 + 0.25 * sin(_angle * 1.7)
	cam.position = Vector3(cos(_angle) * 7.2, y, sin(_angle) * 7.2)
	cam.look_at(Vector3(0, 1.75, 0))


func _process(delta: float) -> void:
	_angle += delta * TAU / 110.0
	_place_cam()
	var speeds := [0.42, -0.3, 0.2]
	for i in _pivots.size():
		(_pivots[i] as Node3D).rotate_object_local(Vector3(0, 1, 0).rotated(Vector3(1, 0, 0), 0.5 * i).normalized(), delta * speeds[i])
		(_pivots[i] as Node3D).rotate_y(delta * 0.12)


## 화면마다 구도/색을 바꿈. offset: 주인공이 화면 어디에 오는지(음수 = 오른쪽), accent: 중심 빛 색.
func set_mode(offset: float, accent := WARM, blur := 0.09, time := 0.9) -> void:
	if _tw:
		_tw.kill()
	_tw = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_property(cam, "h_offset", offset, time)
	_tw.tween_property(cam.attributes, "dof_blur_amount", blur, time)
	_tw.tween_property(_core_light, "light_color", accent, time)
	_tw.tween_property(_core_mat, "emission", accent, time)
	_tw.tween_property(_core_mat, "albedo_color", accent, time)
