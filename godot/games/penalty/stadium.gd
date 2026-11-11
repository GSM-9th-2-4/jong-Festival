extends Node3D
## 페널티킥 경기장: 잔디(줄무늬·라인·풀잎), 골대+그물(셰이더로 출렁), 관중석, LED 광고판, 조명탑.
## 좌표: 골라인 z=0, 골문 x=-3.66~3.66 / y=0~2.44, 페널티 마크 (0,0,11). 카메라는 +z 쪽에서 -z 를 봄.

const GOAL_HALF := 3.66
const GOAL_H := 2.44
const NET_TOP := 1.0      # 그물 윗면 깊이
const NET_BOTTOM := 2.2   # 그물 바닥 깊이

const GRASS_COMMON := """
float px_line(float d, float hw, float aa) { return 1.0 - smoothstep(hw - aa, hw + aa, d); }
float box_line(vec2 p, vec2 c, vec2 hs) {
	vec2 q = abs(p - c) - hs;
	return abs(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0));
}
float pitch_lines(vec2 p, float aa) {
	float hw = 0.06;
	float m = 0.0;
	if (abs(p.x) < 34.06) { m = max(m, px_line(abs(p.y), hw, aa)); }
	if (p.y > -0.06) {
		m = max(m, px_line(box_line(p, vec2(0.0, 2.75), vec2(9.16, 2.75)), hw, aa));
		m = max(m, px_line(box_line(p, vec2(0.0, 8.25), vec2(20.16, 8.25)), hw, aa));
		m = max(m, px_line(abs(abs(p.x) - 34.0), hw, aa));
	}
	m = max(m, px_line(length(p - vec2(0.0, 11.0)), 0.11, aa));
	if (p.y > 16.5) { m = max(m, px_line(abs(length(p - vec2(0.0, 11.0)) - 9.15), hw, aa)); }
	return m;
}
vec3 grass_color(vec2 p) {
	float stripe = smoothstep(0.47, 0.53, abs(fract(p.y / 11.0 + 0.25) - 0.5) * 2.0);
	return mix(vec3(0.040, 0.128, 0.018), vec3(0.090, 0.225, 0.036), stripe);
}
"""

const GROUND_SHADER := """
shader_type spatial;
uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wp;
%s
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float lum = dot(texture(tex_a, p * 0.55).rgb, vec3(0.3, 0.5, 0.2));
	float lum2 = dot(texture(tex_a, p * 0.047 + 0.37).rgb, vec3(0.3, 0.5, 0.2));
	float lum3 = dot(texture(tex_a, p * 2.3 + 0.11).rgb, vec3(0.3, 0.5, 0.2));
	vec3 g = grass_color(p) * (0.45 + lum * 0.9 + lum3 * 0.6) * (0.75 + lum2 * 0.7);
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.7;
	float line = pitch_lines(p, aa) * (0.82 + 0.18 * lum3);
	ALBEDO = mix(g, vec3(0.80, 0.82, 0.78) * (0.75 + lum * 0.5), line);
	ROUGHNESS = mix(0.8, 0.9, line);
	SPECULAR = 0.22;
	NORMAL_MAP = texture(tex_n, p * 0.55).rgb;
	NORMAL_MAP_DEPTH = 1.6;
}
"""

const BLADE_SHADER := """
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
varying vec3 base;
varying float h;
varying float rnd;
%s
void vertex() {
	base = VERTEX;
	h = UV.y;
	rnd = fract(float(INSTANCE_ID) * 0.6180339);
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + NORMAL * 0.35);
}
void fragment() {
	vec2 p = base.xz;
	vec3 g = grass_color(p) * (0.75 + rnd * 0.7);
	float line = pitch_lines(p, 0.01);
	g = mix(g, vec3(0.80, 0.82, 0.78), line * 0.9);
	ALBEDO = g * (0.45 + 0.85 * h);
	ROUGHNESS = 0.85;
	SPECULAR = 0.12;
	BACKLIGHT = vec3(0.015, 0.04, 0.008) * h;
}
"""

const NET_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always, blend_mix;
uniform vec3 hit = vec3(0.0, 1.0, -1.5);
uniform vec3 push = vec3(0.0, 0.0, -1.0);
uniform float amp = 0.0;
uniform float ripple = 0.0;
uniform float t = 0.0;
uniform float cell = 0.12;
uniform float thick = 0.011;
void vertex() {
	float pin = COLOR.r;
	float d = distance(VERTEX, hit);
	float bulge = amp * exp(-d * d / (2.0 * 0.6 * 0.6));
	float wave = ripple * sin(d * 5.0 - t * 20.0) * exp(-d * 0.55) * 0.10;
	vec3 to_hit = hit - VERTEX;
	VERTEX += normalize(push) * (bulge + wave) * pin;
	VERTEX += to_hit * clamp(bulge * 0.9, -0.5, 0.5) * pin;   // 공 쪽으로 그물코가 당겨짐 (정면에서도 보이게)
	VERTEX.y += (wave * 0.7 - bulge * 0.15) * pin;
	VERTEX.z += sin(t * 1.3 + VERTEX.x * 0.8 + VERTEX.y * 1.7) * 0.012 * pin;
}
void fragment() {
	vec2 q = UV / cell;
	vec2 dd = abs(q - round(q)) * cell;
	float d = min(dd.x, dd.y);
	float px = max(max(fwidth(UV.x), fwidth(UV.y)), 0.0001);
	float hw = max(thick * 0.5, px * 0.5);
	float a = clamp((hw - d) / px + 0.5, 0.0, 1.0) * clamp(thick / px, 0.0, 1.0);
	if (a < 0.04) { discard; }
	ALBEDO = vec3(0.86, 0.87, 0.88);
	ROUGHNESS = 0.7;
	ALPHA = a;
}
"""

const CROWD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float cheer = 0.0;
uniform float flash = 0.0;
uniform float t = 0.0;
uniform float bright = 0.5;
float h1(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 g = UV / vec2(0.52, 0.82);
	vec2 id = floor(g);
	float r = h1(id);
	float r2 = h1(id + 17.3);
	float r3 = h1(id + 51.9);
	vec2 f = fract(g);
	f.x += (r2 - 0.5) * 0.16;
	float bob = (0.03 + cheer * 0.10) * sin(t * (5.0 + r * 6.0) + r2 * 40.0) * step(0.25, r3 + cheer);
	f.y += bob;
	vec3 seat = vec3(0.035, 0.045, 0.075) * (0.7 + 0.6 * step(0.5, fract(g.y * 0.5)));
	float aisle = step(0.965, fract(UV.x / 9.4));
	float walk = step(abs(UV.y - 7.4), 0.6);
	float occupied = step(r3, 0.93) * (1.0 - aisle) * (1.0 - walk);
	vec3 pal = vec3(0.75, 0.10, 0.12);
	if (r > 0.80) { pal = vec3(0.85, 0.85, 0.88); }
	else if (r > 0.62) { pal = vec3(0.10, 0.22, 0.65); }
	else if (r > 0.50) { pal = vec3(0.90, 0.68, 0.12); }
	else if (r > 0.38) { pal = vec3(0.08, 0.09, 0.12); }
	else if (r > 0.28) { pal = vec3(0.15, 0.50, 0.28); }
	pal *= 0.6 + r2 * 0.6;
	vec3 skin = mix(vec3(0.80, 0.58, 0.45), vec3(0.42, 0.27, 0.19), step(0.7, r2));
	float body = smoothstep(0.40, 0.30, abs(f.x - 0.5) + max(f.y - 0.28, 0.0) * 0.75) * step(f.y, 0.62);
	float head = smoothstep(0.15, 0.11, length((f - vec2(0.5, 0.25)) * vec2(1.0, 0.82)));
	float arms = cheer * step(0.45, r) * smoothstep(0.07, 0.04, abs(abs(f.x - 0.5) - 0.33)) * step(f.y, 0.5) * step(0.02, f.y);
	vec3 col = seat;
	col = mix(col, pal * (1.15 - f.y * 0.6), body * occupied);
	col = mix(col, pal, arms * occupied);
	col = mix(col, skin, head * occupied);
	col *= bright * (0.8 + 0.4 * UV.y / 18.0);
	float fl = step(1.0 - flash * 0.012, h1(id + floor(t * 14.0) * 3.7)) * occupied;
	col += vec3(9.0, 9.5, 11.0) * fl * smoothstep(0.22, 0.02, length(f - vec2(0.5, 0.3)));
	ALBEDO = col;
}
"""

const LED_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float t = 0.0;
uniform float energy = 2.0;
void fragment() {
	vec2 uv = vec2(UV.x - t * 0.012, UV.y);
	vec3 c = texture(tex, uv).rgb;
	vec2 dots = abs(fract(UV * vec2(1600.0, 28.0)) - 0.5);
	float m = smoothstep(0.5, 0.25, max(dots.x, dots.y));
	ALBEDO = c * energy * (0.55 + 0.45 * m) + vec3(0.004, 0.005, 0.008);
}
"""

var net_mat: ShaderMaterial
var crowd_mat: ShaderMaterial
var led_mat: ShaderMaterial
var spots: Array[SpotLight3D] = []
var _t := 0.0


func build() -> void:
	_pitch()
	_goal()
	_net()
	_stand()
	_boards()
	_lights()


func _process(dt: float) -> void:
	_t += dt
	net_mat.set_shader_parameter("t", _t)
	crowd_mat.set_shader_parameter("t", _t)
	led_mat.set_shader_parameter("t", _t)


func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	if not shadow:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


# ---------- 잔디 ----------

func _pitch() -> void:
	var src := Kit.pbr("leafy_grass")
	var gm := _shader_mat(GROUND_SHADER % GRASS_COMMON)
	gm.set_shader_parameter("tex_a", src.albedo_texture)
	gm.set_shader_parameter("tex_n", src.normal_texture)
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 110)
	_mi(plane, gm, Vector3(0, 0, 20), false)

	# 카메라 앞쪽에만 실제 풀잎 (삼각형 하나짜리 잎을 대량으로)
	var blade := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.004, 0, 0), Vector3(0.004, 0, 0), Vector3(0.001, 1, 0.25)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1)])
	blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = blade
	var n := 170000
	mm.instance_count = n
	var buf := PackedFloat32Array()
	buf.resize(n * 12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		# 카메라 가까이에 더 촘촘하게
		var z := 17.4 - pow(rng.randf(), 1.6) * 9.5
		var x := rng.randf_range(-1.0, 1.0) * (1.0 + (17.4 - z) * 0.5)
		var a := rng.randf() * TAU
		var hgt := rng.randf_range(0.02, 0.036) * clampf((z - 7.9) / 2.5, 0.05, 1.0)
		var w := rng.randf_range(0.8, 1.5)
		var c := cos(a)
		var s := sin(a)
		var o := i * 12
		buf[o] = c * w
		buf[o + 1] = 0.0
		buf[o + 2] = s * hgt
		buf[o + 3] = x
		buf[o + 4] = 0.0
		buf[o + 5] = hgt
		buf[o + 6] = 0.0
		buf[o + 7] = 0.0
		buf[o + 8] = -s * w
		buf[o + 9] = 0.0
		buf[o + 10] = c * hgt
		buf[o + 11] = z
	mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _shader_mat(BLADE_SHADER % GRASS_COMMON)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-8, 0, 6), Vector3(16, 0.2, 12))
	add_child(mmi)


# ---------- 골대 ----------

func _tube(a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 20
	var m := _mi(cyl, mat, (a + b) / 2)
	var dir := (b - a).normalized()
	if absf(dir.y) < 0.999:
		m.quaternion = Quaternion(Vector3.UP, dir)


func _goal() -> void:
	var white := Kit.plain(Color(0.93, 0.93, 0.92), 0.0, 0.28)
	var grey := Kit.plain(Color(0.45, 0.46, 0.48), 0.6, 0.4)
	var r := 0.06
	var x := GOAL_HALF + r
	var top := GOAL_H + r
	for s in [-1.0, 1.0]:
		_tube(Vector3(s * x, 0, 0), Vector3(s * x, top + r, 0), r, white)
		# 그물 받침대
		_tube(Vector3(s * x, top, 0), Vector3(s * x, top, -NET_TOP), 0.022, grey)
		_tube(Vector3(s * x, top, -NET_TOP), Vector3(s * x, 0, -NET_BOTTOM), 0.022, grey)
		_tube(Vector3(s * x, 0.022, 0), Vector3(s * x, 0.022, -NET_BOTTOM), 0.022, grey)
		var cap := SphereMesh.new()
		cap.radius = r
		cap.height = r * 2
		_mi(cap, white, Vector3(s * x, top, 0))
	_tube(Vector3(-x, top, 0), Vector3(x, top, 0), r, white)
	_tube(Vector3(-x, top, -NET_TOP), Vector3(x, top, -NET_TOP), 0.018, grey)
	_tube(Vector3(-x, 0.022, -NET_BOTTOM), Vector3(x, 0.022, -NET_BOTTOM), 0.022, grey)


static func net_back_z(y: float) -> float:  ## 높이 y 에서 뒷그물의 z
	return -lerpf(NET_BOTTOM, NET_TOP, clampf(y / GOAL_H, 0.0, 1.0))


func _net() -> void:
	net_mat = _shader_mat(NET_SHADER)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var h := GOAL_HALF
	# 각 면: f(a, b) → 위치, 크기(미터)로 UV
	var panels := [
		[func(a: float, b: float): return Vector3(lerpf(-h, h, a), GOAL_H * b, net_back_z(GOAL_H * b)), Vector2(7.32, 2.72), Vector3(0, 0.4, 1).normalized()],
		[func(a: float, b: float): return Vector3(lerpf(-h, h, a), GOAL_H + 0.03 - 0.10 * sin(b * PI), -NET_TOP * b), Vector2(7.32, 1.0), Vector3.UP],
		[func(a: float, b: float): return Vector3(-h, GOAL_H * b, net_back_z(GOAL_H * b) * a), Vector2(1.6, 2.44), Vector3.RIGHT],
		[func(a: float, b: float): return Vector3(h, GOAL_H * b, net_back_z(GOAL_H * b) * a), Vector2(1.6, 2.44), Vector3.LEFT],
	]
	for p in panels:
		var f: Callable = p[0]
		var size: Vector2 = p[1]
		var na := int(ceil(size.x / 0.14))
		var nb := int(ceil(size.y / 0.14))
		var start := verts.size()
		for j in nb + 1:
			for i in na + 1:
				var a := float(i) / na
				var b := float(j) / nb
				var v: Vector3 = f.call(a, b)
				verts.append(v)
				norms.append(p[2])
				uvs.append(Vector2(a * size.x, b * size.y))
				var pin := clampf(minf(v.y / 0.5, -v.z / 0.45), 0.0, 1.0)
				cols.append(Color(pin, 0, 0))
		for j in nb:
			for i in na:
				var k := start + j * (na + 1) + i
				idx.append_array([k, k + 1, k + na + 1, k + 1, k + na + 2, k + na + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := _mi(mesh, net_mat, Vector3.ZERO, false)
	m.custom_aabb = AABB(Vector3(-5, -0.5, -4), Vector3(10, 4, 5))


func net_hit(pos: Vector3, dir: Vector3) -> void:
	net_mat.set_shader_parameter("hit", pos)
	net_mat.set_shader_parameter("push", dir)


func net_state(amp: float, ripple: float) -> void:
	net_mat.set_shader_parameter("amp", amp)
	net_mat.set_shader_parameter("ripple", ripple)


# ---------- 관중석 ----------

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv: Vector2) -> ArrayMesh:  # a-b 아래, d-c 위
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var nrm := (b - a).cross(d - a).normalized()
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c, d])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([nrm, nrm, nrm, nrm])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, uv.y), Vector2(uv.x, uv.y), Vector2(uv.x, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _stand() -> void:
	crowd_mat = _shader_mat(CROWD_SHADER)
	var w := 75.0
	var z0 := -10.0
	var z1 := -23.0
	var y0 := 1.9
	var y1 := 8.8
	var slope := Vector2(z1 - z0, y1 - y0).length()
	_mi(_quad(Vector3(-w, y0, z0), Vector3(w, y0, z0), Vector3(w, y1, z1), Vector3(-w, y1, z1), Vector2(w * 2, slope)), crowd_mat, Vector3.ZERO, false)
	# 양옆 스탠드 (화면 가장자리)
	for s in [-1.0, 1.0]:
		_mi(_quad(Vector3(s * 44, y0, 40), Vector3(s * 44, y0, z0), Vector3(s * 61, y1, z0), Vector3(s * 61, y1, 40), Vector2(40 - z0, slope)), crowd_mat, Vector3.ZERO, false)
	# 앞 벽 + 뒤 벽 + 지붕
	var conc := Kit.pbr("concrete_floor", Vector3(40, 1, 1), Color(0.16, 0.17, 0.2))
	var wall := BoxMesh.new()
	wall.size = Vector3(w * 2, y0, 0.4)
	_mi(wall, conc, Vector3(0, y0 / 2, z0 + 0.2))
	var dark := Kit.plain(Color(0.03, 0.035, 0.05), 0.3, 0.6)
	var back := BoxMesh.new()
	back.size = Vector3(w * 2, 4.0, 0.5)
	_mi(back, dark, Vector3(0, y1 + 1.0, z1 - 0.3), false)
	var roof := BoxMesh.new()
	roof.size = Vector3(w * 2, 0.5, 16.0)
	var rf := _mi(roof, dark, Vector3(0, 11.2, -18.6), false)
	rf.rotation_degrees.x = 5.0
	var fascia := BoxMesh.new()
	fascia.size = Vector3(w * 2, 0.10, 0.1)
	_mi(fascia, Kit.emissive(Color(0.75, 0.86, 1.0), 2.5), Vector3(0, 10.35, -10.6), false)


func _boards() -> void:
	# LED 광고판: 글자를 SubViewport 에 한 번 그려서 텍스처로 사용
	var vp := SubViewport.new()
	vp.size = Vector2i(2048, 96)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.012, 0.03)
	bg.size = Vector2(2048, 96)
	vp.add_child(bg)
	var items := [["FESTIVAL CUP", true, Color(1.0, 0.62, 0.12)], ["할인 쿠폰 GET", false, Color(0.4, 0.82, 1.0)],
		["PENALTY SHOOTOUT", true, Color(0.95, 0.95, 1.0)], ["단 한 번의 슛!", false, Color(0.55, 1.0, 0.55)]]
	for i in items.size():
		var l := Label.new()
		l.text = items[i][0]
		l.label_settings = Kit.label_settings(64 if items[i][1] else 54, items[i][2], items[i][1], 0, false)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.position = Vector2(i * 512, 0)
		l.size = Vector2(512, 96)
		vp.add_child(l)
	led_mat = _shader_mat(LED_SHADER)
	led_mat.set_shader_parameter("tex", vp.get_texture())
	var z := -7.0
	var wdt := 70.0
	_mi(_quad(Vector3(-wdt, 0.05, z), Vector3(wdt, 0.05, z), Vector3(wdt, 1.0, z - 0.12), Vector3(-wdt, 1.0, z - 0.12), Vector2(wdt * 2 / 20.3, 1)), led_mat, Vector3.ZERO, false)
	var box := BoxMesh.new()
	box.size = Vector3(wdt * 2, 1.0, 0.3)
	_mi(box, Kit.plain(Color(0.02, 0.02, 0.025), 0.2, 0.5), Vector3(0, 0.5, z - 0.3))


# ---------- 조명 ----------

func _lamp_bank(pos: Vector3, target: Vector3, cols: int, rows: int, lamp := 0.42, energy := 14.0) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.look_at(target)
	var back := BoxMesh.new()
	back.size = Vector3(cols * lamp * 1.25 + 0.2, rows * lamp * 1.25 + 0.2, 0.25)
	var bm := MeshInstance3D.new()
	bm.mesh = back
	bm.material_override = Kit.plain(Color(0.03, 0.03, 0.035), 0.5, 0.5)
	bm.position.z = 0.15
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bm)
	var disc := SphereMesh.new()
	disc.radius = lamp * 0.5
	disc.height = lamp * 0.5
	var mat := Kit.emissive(Color(0.86, 0.92, 1.0), energy)
	for j in rows:
		for i in cols:
			var l := MeshInstance3D.new()
			l.mesh = disc
			l.material_override = mat
			l.rotation_degrees.x = 90
			l.position = Vector3((i - (cols - 1) * 0.5) * lamp * 1.25, (j - (rows - 1) * 0.5) * lamp * 1.25, 0)
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(l)


func _spot(pos: Vector3, target: Vector3, energy: float, fog: float, color := Color(0.90, 0.95, 1.0)) -> SpotLight3D:
	var s := SpotLight3D.new()
	add_child(s)
	s.position = pos
	s.look_at(target)
	s.light_color = color
	s.light_energy = energy
	s.spot_range = 110.0
	s.spot_attenuation = 0.25
	s.spot_angle = 30.0
	s.spot_angle_attenuation = 0.6
	s.shadow_enabled = true
	s.shadow_blur = 1.6
	s.shadow_bias = 0.06
	s.light_volumetric_fog_energy = fog
	s.light_specular = 0.6
	spots.append(s)
	return s


func _lights() -> void:
	var aim := Vector3(0, 0, 6)
	# 지붕 끝 조명 줄 (화면 위쪽에 보이는 눈부신 조명)
	for i in 9:
		var x := (i - 4) * 7.5
		_lamp_bank(Vector3(x, 9.75, -10.3), Vector3(x * 0.5, 0, 8), 4, 1, 0.34, 16.0)
	# 모서리 조명탑
	var steel := Kit.plain(Color(0.10, 0.11, 0.13), 0.7, 0.45)
	for s in [-1.0, 1.0]:
		var base := Vector3(s * 24, 0, -36)
		_tube(base, base + Vector3(0, 33, 0), 0.5, steel)
		_lamp_bank(base + Vector3(-s * 0.5, 34, 1.0), aim, 6, 5, 0.55, 9.0)
	# 실제 광원 4개: 뒤쪽 2개(역광·안개 빛줄기) + 카메라 뒤 2개(정면 주광) → 선수 그림자가 네 갈래
	_spot(Vector3(-17, 9.7, -10.2), Vector3(3, 0, 7), 4.5, 0.6)
	_spot(Vector3(17, 9.7, -10.2), Vector3(-3, 0, 7), 4.5, 0.6)
	_spot(Vector3(-24, 26, 40), Vector3(2, 0, 1), 6.0, 0.0, Color(1.0, 0.97, 0.92))
	_spot(Vector3(24, 26, 40), Vector3(-2, 0, 1), 6.0, 0.0, Color(1.0, 0.97, 0.92))
