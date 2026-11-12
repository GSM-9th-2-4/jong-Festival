extends Node3D
## 사람 모델 공용 뼈대: Microsoft Rocketbox 아바타(MIT)를 실행 중에 FBX 로 읽어, 뼈를 자세 값대로 직접 움직임.
## 골키퍼(keeper_human.gd)와 키커(kicker.gd)가 같이 씀. 모델 파일은 `python3 godot/games/penalty/fetch_keeper.py` 로 받음.
##
## 자세 = 관절 각도 묶음(Dictionary, 값은 전부 Vector3 도 단위). keeper.gd(캡슐 인형)와 같은 약속:
##   +z 를 바라봄. L = +x 쪽. 각도가 0 이면 팔다리는 관절에서 -y 로 곧게 내려옴.
##   x 회전: 음수 = 앞으로 듦(팔/허벅지), 양수 = 무릎 굽힘·몸 숙임.  z 회전: 양수 = 팔다리를 바깥으로 벌림.
##   오른쪽(R) 관절 값은 "왼쪽이라고 생각하고" 적음 — 풀 때 좌우를 뒤집어 줌. 그래서 대칭 자세는 L 과 R 값이 같음.
##   tw = (윗팔 비틀기, 아래팔 비틀기): 양수면 손바닥이 앞(+z)을 향함.
##   ik = (왼발, 오른발) 발을 목표(ftL/ftR = 발목 위치, 이 노드 기준 m)에 붙이는 정도 0~1. 0 이면 thigh/shin/foot 각도를 그대로 씀.
##   fp = IK 로 붙인 발의 (발끝 내림 각, 발끝 바깥 각).

const AVATARS := {  # 이름 → 폴더(assets/models/…), FBX, 텍스처 접두어
	"keeper": {"dir": "rocketbox_sports_male_02", "fbx": "Sports_Male_02.fbx", "tex": "m301"},
	"kicker": {"dir": "rocketbox_sports_male_03", "fbx": "Sports_Male_03.fbx", "tex": "m300"},
}
const MODEL_HEIGHT := 1.805   # 원본 모델 키 (m)
const DEG := PI / 180.0
const ANKLE := 0.108          # 서 있을 때 발목 높이 (m)

const SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 kit : source_color = vec3(0.95, 0.74, 0.06);
uniform vec3 trim : source_color = vec3(0.025, 0.025, 0.03);
uniform vec3 glove : source_color = vec3(0.90, 0.91, 0.93);
uniform float dye = 0.0;     // 1 = 상의·양말을 kit 색으로 물들임 (골키퍼 유니폼)
uniform float gloves = 0.0;  // 1 = 손을 장갑으로

float box(vec2 uv, vec4 r) {
	vec2 s = step(r.xy, uv) * step(uv, r.zw);
	return s.x * s.y;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float gr = c.g / max(c.r, 0.001);
	float br = c.b / max(c.r, 0.001);
	// 살색: 붉은 기가 도는 중간 밝기
	float skin = smoothstep(0.22, 0.32, gr) * (1.0 - smoothstep(0.72, 0.82, gr)) * (1.0 - smoothstep(0.55, 0.7, br)) * smoothstep(0.08, 0.16, c.r);
	float orange = (1.0 - smoothstep(0.12, 0.26, gr)) * smoothstep(0.12, 0.25, c.r);
	// 옷감 위치 (텍스처 좌표): 상의(앞·뒤·소매), 양말
	float shirt = max(max(box(UV, vec4(0.262, 0.30, 0.762, 0.66)), box(UV, vec4(0.33, 0.57, 0.70, 0.87))), box(UV, vec4(0.355, 0.07, 0.66, 0.32)));
	float socks = max(box(UV, vec4(0.0, 0.312, 0.262, 0.575)), box(UV, vec4(0.762, 0.312, 1.0, 0.575)));
	float cloth = max(shirt, socks) * (1.0 - skin) * dye;
	vec3 dyed = kit * mix(0.50, 1.0, smoothstep(0.02, 0.55, lum));
	dyed = mix(dyed, trim * (0.6 + lum), orange);
	// 골키퍼 장갑: 손 부분을 흰 장갑으로, 손목에 검은 띠
	float hand = smoothstep(0.826, 0.838, UV.y) * max(step(UV.x, 0.30), step(0.70, UV.x)) * skin * gloves;
	vec3 g = glove * mix(0.62, 1.0, smoothstep(0.08, 0.5, lum));
	g = mix(g, trim, (1.0 - smoothstep(0.858, 0.866, UV.y)));
	c = mix(c, dyed, cloth);
	c = mix(c, g, hand);
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
	float bare = skin * (1.0 - hand) * (1.0 - cloth);
	ROUGHNESS = mix(0.84, 0.56, bare);
	SPECULAR = mix(0.35, 0.45, bare);
}
"""

# 뼈 이름 → 자세 관절
const B_ROOT := "Bip01"
const SIDES := ["L", "R"]

var _skel: Skeleton3D
var _scale := 1.0
var _n := 0
var _par := PackedInt32Array()
var _lo: Array[Vector3] = []      # 부모 기준 쉬는 자세 위치
var _lb: Array[Basis] = []        # 부모 기준 쉬는 자세 회전
var _cr: Array[Basis] = []        # (-y 로 곧게 펴는 보정) * 쉬는 자세 전역 회전
var _want: Array = []             # 이번 자세에서 정해 준 전역 회전 (없으면 null)
var _g: Array[Transform3D] = []   # 마지막으로 푼 전역 뼈 자세 (모델 좌표)
var _ctl := PackedInt32Array()    # 직접 움직이는 뼈
var _b := {}                      # 이름 → 뼈 번호
var _len_thigh := 0.4
var _len_calf := 0.4

var _cur := {}        # 지금 자세
var _av := {}         # 쓰는 모델 (AVATARS 의 한 줄)
var _dir := ""


static func model_dir(avatar: String) -> String:
	return Kit.assets_dir() + "/models/" + AVATARS[avatar]["dir"]


static func available(avatar: String) -> bool:
	var d := model_dir(avatar)
	var a: Dictionary = AVATARS[avatar]
	return FileAccess.file_exists(d + "/" + a["fbx"]) and FileAccess.file_exists(d + "/" + a["tex"] + "_body_color.tga") \
		and FileAccess.file_exists(d + "/" + a["tex"] + "_head_color.tga")


## 모델을 읽어 세움. 실패하면 false (그때는 캡슐 인형을 쓰면 됨).
## look: {"height": 키(m), "kit": 유니폼 색(없으면 원래 무늬 그대로), "gloves": 장갑 여부}
func setup(avatar: String, look := {}) -> bool:
	_av = AVATARS[avatar]
	_dir = model_dir(avatar) + "/"
	var doc := FBXDocument.new()
	var st := FBXState.new()
	st.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_DISCARD_TEXTURES  # 텍스처는 아래에서 직접 붙임
	# FBX 안에 적힌 텍스처 경로는 만든 사람 PC 기준이라 못 찾는 게 정상 → 그 오류 출력만 잠깐 끔
	var was := Engine.print_error_messages
	Engine.print_error_messages = false
	var err := doc.append_from_file(_dir + _av["fbx"], st)
	Engine.print_error_messages = was
	if err != OK:
		return false
	var scene := doc.generate_scene(st) as Node3D
	if scene == null:
		return false
	_skel = _find(scene, "Skeleton3D") as Skeleton3D
	var mesh := _find(scene, "MeshInstance3D") as MeshInstance3D
	if _skel == null or mesh == null or _skel.find_bone("Bip01 L Hand") < 0:
		scene.free()
		return false
	var anim := _find(scene, "AnimationPlayer")
	if anim != null:
		anim.get_parent().remove_child(anim)
		anim.free()
	_scale = float(look.get("height", 1.85)) / MODEL_HEIGHT
	scene.scale = Vector3.ONE * _scale
	add_child(scene)
	_materials(mesh, look)
	mesh.extra_cull_margin = 2.0
	_rig(1.22 if look.get("gloves", false) else 1.0)
	_apply(stand())
	return true


func _find(n: Node, type: String) -> Node:
	if n.is_class(type):
		return n
	for c in n.get_children():
		var r := _find(c, type)
		if r != null:
			return r
	return null


func _materials(mesh: MeshInstance3D, look: Dictionary) -> void:
	var d: String = _dir + _av["tex"]
	for i in mesh.mesh.get_surface_count():
		var src := mesh.mesh.surface_get_material(i)
		var mname := src.resource_name if src != null else ""
		if "opacity" in mname:  # 머리카락 가닥 (투명 무늬)
			var hm := StandardMaterial3D.new()
			hm.albedo_texture = Kit.texture(d + "_opacity_color.tga")
			hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			hm.alpha_scissor_threshold = 0.4
			hm.cull_mode = BaseMaterial3D.CULL_DISABLED
			hm.roughness = 0.7
			hm.metallic_specular = 0.2
			hm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mesh.set_surface_override_material(i, hm)
		elif "head" in mname:
			var m := StandardMaterial3D.new()
			m.albedo_texture = Kit.texture(d + "_head_color.tga")
			var nt := Kit.texture(d + "_head_normal.tga")
			if nt != null:
				m.normal_enabled = true
				m.normal_texture = nt
			m.roughness = 0.58
			m.metallic_specular = 0.45
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mesh.set_surface_override_material(i, m)
		else:
			var sh := Shader.new()
			sh.code = SHADER
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("albedo_tex", Kit.texture(d + "_body_color.tga"))
			sm.set_shader_parameter("normal_tex", Kit.texture(d + "_body_normal.tga"))
			if look.has("kit"):
				sm.set_shader_parameter("kit", look["kit"])
				sm.set_shader_parameter("dye", 1.0)
			sm.set_shader_parameter("gloves", 1.0 if look.get("gloves", false) else 0.0)
			mesh.set_surface_override_material(i, sm)


func _rig(hand_scale: float) -> void:
	_skel.reset_bone_poses()
	_n = _skel.get_bone_count()
	_par.resize(_n)
	_lo.resize(_n)
	_lb.resize(_n)
	_cr.resize(_n)
	_want.resize(_n)
	_g.resize(_n)
	for i in _n:
		_par[i] = _skel.get_bone_parent(i)
		var r := _skel.get_bone_rest(i)
		_lo[i] = r.origin
		_lb[i] = r.basis.orthonormalized()
		_cr[i] = _skel.get_bone_global_rest(i).basis.orthonormalized()
		_b[_skel.get_bone_name(i)] = i
	# 팔다리는 쉬는 자세(A 자)에서 -y 로 곧게 편 것을 0 도로 삼음
	for s in SIDES:
		for part in ["UpperArm", "Forearm", "Hand", "Thigh", "Calf"]:
			var i: int = _b["Bip01 %s %s" % [s, part]]
			var dir := _cr[i].x.normalized()
			_cr[i] = Basis(Quaternion(dir, Vector3.DOWN)) * _cr[i]
	_len_thigh = _lo[_b["Bip01 L Calf"]].length()
	_len_calf = _lo[_b["Bip01 L Foot"]].length()
	var names := [B_ROOT, "Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2", "Bip01 Neck", "Bip01 Head"]
	for s in SIDES:
		for part in ["Clavicle", "UpperArm", "Forearm", "Hand", "Thigh", "Calf", "Foot"]:
			names.append("Bip01 %s %s" % [s, part])
	for nm in names:
		_ctl.append(_b[nm])
	for s in SIDES:  # 장갑 낀 손은 조금 두툼하게
		_skel.set_bone_pose_scale(_b["Bip01 %s Hand" % s], Vector3.ONE * hand_scale)


# ---------- 자세 풀기 ----------

static func _e(v: Vector3) -> Basis:
	return Basis.from_euler(v * DEG)


static func _es(v: Vector3, sgn: float) -> Basis:  # 오른쪽은 좌우를 뒤집음
	return Basis.from_euler(Vector3(v.x, v.y * sgn, v.z * sgn) * DEG)


static func _aim(dir: Vector3, fwd: Vector3) -> Basis:  # -y 가 dir 을 향하고 z 가 되도록 fwd 쪽인 틀
	var y := -dir.normalized()
	var z := (fwd - y * fwd.dot(y)).normalized()
	return Basis(y.cross(z), y, z)


func _put(bone: String, g: Basis) -> void:
	var i: int = _b[bone]
	_want[i] = g * _cr[i]


func _solve(p: Dictionary) -> void:
	_want.fill(null)
	var gp := _e(p["rot"])
	var sp: Vector3 = p["spine"]
	var g1 := gp * _e(sp * 0.5)
	var g2 := g1 * _e(sp * 0.5)
	var hd: Vector3 = p["head"]
	var gn := g2 * _e(hd * 0.4)
	_put(B_ROOT, gp)
	_put("Bip01 Pelvis", gp)
	_put("Bip01 Spine", gp)
	_put("Bip01 Spine1", g1)
	_put("Bip01 Spine2", g2)
	_put("Bip01 Neck", gn)
	_put("Bip01 Head", gn * _e(hd * 0.6))
	for i in 2:
		var s: String = SIDES[i]
		var sgn := 1.0 if i == 0 else -1.0
		var tw: Vector3 = p["tw" + s]
		var ga := g2 * _es(p["arm" + s], sgn) * Basis(Vector3.UP, tw.x * sgn * DEG)
		var gf := ga * _es(p["fore" + s], sgn) * Basis(Vector3.UP, tw.y * sgn * DEG)
		# 팔을 들면 어깨(쇄골)도 같이 올라감
		var up := (g2.inverse() * (ga * Vector3.DOWN)).y
		var lift := clampf(up * 0.7 + 0.2, 0.0, 1.0) * 26.0
		_put("Bip01 %s Clavicle" % s, g2 * Basis(Vector3.BACK, lift * sgn * DEG))
		_put("Bip01 %s UpperArm" % s, ga)
		_put("Bip01 %s Forearm" % s, gf)
		_put("Bip01 %s Hand" % s, gf * _es(p["hand" + s], sgn))
		var gt := gp * _es(p["thigh" + s], sgn)
		var gs := gt * _es(p["shin" + s], sgn)
		_put("Bip01 %s Thigh" % s, gt)
		_put("Bip01 %s Calf" % s, gs)
		_put("Bip01 %s Foot" % s, gs * _es(p["foot" + s], sgn))
	var ik: Vector3 = p["ik"]
	var thigh_l: int = _b["Bip01 L Thigh"]
	var thigh_r: int = _b["Bip01 R Thigh"]
	for b in _n:
		var par := _par[b]
		var origin: Vector3
		if par < 0:
			origin = (p["pos"] as Vector3) / _scale
		else:
			origin = _g[par].origin + _g[par].basis * _lo[b]
		if b == thigh_l and ik.x > 0.001:
			_leg_ik("L", 1.0, origin, (p["ftL"] as Vector3) / _scale, ik.x, p["fpL"])
		elif b == thigh_r and ik.y > 0.001:
			_leg_ik("R", -1.0, origin, (p["ftR"] as Vector3) / _scale, ik.y, p["fpR"])
		var basis: Basis
		if _want[b] != null:
			basis = _want[b]
		elif par >= 0:
			basis = _g[par].basis * _lb[b]
		else:
			basis = _lb[b]
		_g[b] = Transform3D(basis, origin)


## 다리 두 마디 IK: 엉덩이 → 발목 목표. 무릎은 앞(조금 바깥)으로.
func _leg_ik(s: String, sgn: float, hip: Vector3, target: Vector3, w: float, fp: Vector3) -> void:
	var l1 := _len_thigh
	var l2 := _len_calf
	var v := target - hip
	var d := clampf(v.length(), 0.08, (l1 + l2) * 0.998)
	var dir := v.normalized()
	var pole := Vector3(sgn * 0.42, 0.0, 1.0).normalized()
	var perp := (pole - dir * pole.dot(dir)).normalized()
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var knee := hip + dir * (l1 * ca) + perp * (l1 * sqrt(1.0 - ca * ca))
	var ankle := hip + dir * d
	var it: int = _b["Bip01 %s Thigh" % s]
	var ic: int = _b["Bip01 %s Calf" % s]
	var ift: int = _b["Bip01 %s Foot" % s]
	var bt := _aim(knee - hip, perp) * _cr[it]
	var bc := _aim(ankle - knee, perp) * _cr[ic]
	var bf := Basis(Vector3.UP, sgn * fp.y * DEG) * Basis(Vector3.RIGHT, fp.x * DEG) * _cr[ift]  # 발바닥 방향은 fp 로
	_want[it] = (_want[it] as Basis).orthonormalized().slerp(bt.orthonormalized(), w)
	_want[ic] = (_want[ic] as Basis).orthonormalized().slerp(bc.orthonormalized(), w)
	_want[ift] = (_want[ift] as Basis).orthonormalized().slerp(bf.orthonormalized(), w)


func _apply(p: Dictionary) -> void:
	_cur = p
	_solve(p)
	for b in _ctl:
		var par := _par[b]
		var lb: Basis = _g[b].basis if par < 0 else _g[par].basis.inverse() * _g[b].basis
		_skel.set_bone_pose_rotation(b, lb.get_rotation_quaternion())
	_skel.set_bone_pose_position(_b[B_ROOT], _g[_b[B_ROOT]].origin)


func apply(p: Dictionary) -> void:
	_apply(p)


func bone_world(bone: String) -> Vector3:  ## 뼈 위치 (월드 좌표, 마지막으로 적용한 자세)
	return _skel.global_transform * _g[_b[bone]].origin


# ---------- 자세 도구 ----------

static func stand() -> Dictionary:  # 편하게 선 자세. 모든 자세는 여기서 값을 바꿔 만듦 (키가 같아야 섞을 수 있음)
	return {
		"pos": Vector3(0, 0.915, 0), "rot": Vector3(0, 0, 0),
		"spine": Vector3(2, 0, 0), "head": Vector3(0, 0, 0),
		"armL": Vector3(2, 0, 9), "armR": Vector3(2, 0, 9),
		"foreL": Vector3(-14, 0, 0), "foreR": Vector3(-14, 0, 0),
		"handL": Vector3(0, 0, 0), "handR": Vector3(0, 0, 0),
		"twL": Vector3(0, 20, 0), "twR": Vector3(0, 20, 0),
		"thighL": Vector3(-2, 0, 3), "thighR": Vector3(-2, 0, 3),
		"shinL": Vector3(4, 0, 0), "shinR": Vector3(4, 0, 0),
		"footL": Vector3(0, 0, 0), "footR": Vector3(0, 0, 0),
		"ik": Vector3(1, 1, 0),
		"ftL": Vector3(0.12, ANKLE, 0.0), "ftR": Vector3(-0.12, ANKLE, 0.0),
		"fpL": Vector3(0, 14, 0), "fpR": Vector3(0, 14, 0),
	}


static func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = (a[k] as Vector3).lerp(b[k], t)
	return out


static func _mirror(p: Dictionary) -> Dictionary:  # 좌우 뒤집기 (+x 쪽 다이브 → -x 쪽 다이브)
	var out := {}
	for k: String in p:
		var v: Vector3 = p[k]
		if k == "pos":
			out[k] = Vector3(-v.x, v.y, v.z)
		elif k == "rot" or k == "spine" or k == "head":
			out[k] = Vector3(v.x, -v.y, -v.z)
		elif k == "ik":
			out[k] = Vector3(v.y, v.x, 0)
		elif k == "fpL" or k == "fpR":
			out["fpR" if k == "fpL" else "fpL"] = v
		elif k == "ftL":
			out["ftR"] = Vector3(-v.x, v.y, v.z)
		elif k == "ftR":
			out["ftL"] = Vector3(-v.x, v.y, v.z)
		elif k.ends_with("L"):
			out[k.left(-1) + "R"] = v
		else:
			out[k.left(-1) + "L"] = v
	return out
