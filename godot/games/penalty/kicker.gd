extends Node3D
## 키커: 공 뒤에서 기다리다가 → 도움닫기 두 걸음 → 디딤발(왼발)을 공 옆에 딛고 → 오른발로 참 → 결과에 맞는 반응.
## 사람 모델(human.gd, Rocketbox)이 있으면 그걸 쓰고, 없으면 캡슐 인형(keeper.gd)으로 같은 동작을 함.
## 이 노드의 원점은 공(땅 높이), +z 는 달려가는 방향. 자세 약속은 human.gd 참고 (L = +x = 디딤발 쪽).
## 발은 전부 IK(ftL/ftR)로 놓음 — 차는 발의 마지막 목표가 공 자리라서, run(1.0) 이 정확히 "발이 공에 닿는 순간".

const Human := preload("res://games/penalty/human.gd")
const Puppet := preload("res://games/penalty/keeper.gd")

const RUN_TIME := 0.82      ## 누른 뒤 공을 찰 때까지 (초)
const FOLLOW_TIME := 0.55   ## 찬 뒤 다리를 휘두르고 내려놓기까지
const A := 0.108            # 발목 높이
const START_Z := -1.70      # 기다리는 자리 (공 뒤로)
const END_Z := -0.22        # 차는 순간 골반 위치
const PX := 0.10            # 골반은 공보다 살짝 디딤발 쪽

const L0 := Vector3(0.22, A, START_Z + 0.05)
const R0 := Vector3(-0.03, A, START_Z - 0.10)
const R1 := Vector3(-0.03, A, -1.02)      # 첫 걸음 (오른발)
const L1 := Vector3(0.27, A, -0.05)       # 디딤발: 공 바로 옆
const BACK := Vector3(-0.08, 0.60, -0.84) # 오른발을 뒤로 젖힌 꼭대기
const HIT := Vector3(-0.02, 0.135, -0.15) # 공에 닿는 순간의 발목
const PEAK := Vector3(0.20, 0.72, 1.14)   # 차고 난 뒤 발이 올라간 꼭대기
const R2 := Vector3(0.20, A, 0.80)        # 찬 발이 내려앉는 곳 (몸이 디딤발 쪽으로 흘러감)
const L2 := Vector3(0.47, A, 0.50)
const END_POS := Vector3(PX + 0.23, 0.905, 0.62)

var human := false
var _body: Node3D


func build() -> void:
	for avatar in ["kicker", "keeper"]:  # 키커 모델이 없으면 골키퍼 모델에 줄무늬 유니폼 그대로
		if Human.available(avatar):
			var h: Node3D = Human.new()
			add_child(h)
			if h.setup(avatar, {"height": 1.82}):
				_body = h
				human = true
				break
			remove_child(h)
			h.free()
	if _body == null:  # 캡슐 인형: 흰 유니폼, 맨손
		_body = Puppet.new()
		add_child(_body)
		var skin := Color(0.74, 0.53, 0.42)
		_body.build({"jersey": Color(0.90, 0.90, 0.92), "sock": Color(0.88, 0.88, 0.90), "glove": skin})
	_show(_run_pose(0.0))


# ---------- 바깥에서 부르는 것 ----------

func wait(t: float) -> void:  ## 기다림: 숨 쉬고 무게중심을 조금씩 옮김
	var p := _run_pose(0.0)
	var br := sin(t * 1.9)
	var sw := sin(t * 0.8)
	p["pos"] += Vector3(0.018 * sw, 0.004 * br, 0)
	p["rot"] += Vector3(0, 0, -1.2 * sw)
	p["spine"] += Vector3(1.6 * br, 0, 1.5 * sw)
	p["armL"] += Vector3(1.5 * br, 0, 1.0 * br)
	p["armR"] += Vector3(-1.5 * br, 0, 1.0 * br)
	p["foreL"] += Vector3(-3.0 * sw, 0, 0)
	_show(p)


func run(u: float) -> void:  ## 도움닫기 0 → 1 (1 = 발이 공에 닿음)
	_show(_run_pose(clampf(u, 0.0, 1.0)))


## 찬 뒤. t: 찬 뒤 흐른 시간, res_t: 결과가 나온 뒤 흐른 시간(아직이면 음수), result: goal/save/miss
func after(t: float, res_t: float, result: String, rank: int) -> void:
	var p := _follow_pose(t / FOLLOW_TIME) if t < FOLLOW_TIME else _watch_pose(t)
	if res_t >= 0.0:
		var w := smoothstep(0.0, 0.38, res_t)
		p = Human._blend(p, _react_pose(res_t, result, rank), w)
	_show(p)


# ---------- 자세 ----------

static func _kf(u: float, ks: Array) -> Vector3:  # ks = [시각, 값, 시각, 값, …] 사이를 부드럽게 이음
	if u <= ks[0]:
		return ks[1]
	var i := 0
	while i + 2 < ks.size():
		if u <= ks[i + 2]:
			var t: float = (u - ks[i]) / (ks[i + 2] - ks[i])
			return (ks[i + 1] as Vector3).lerp(ks[i + 3], lerpf(t, smoothstep(0.0, 1.0, t), 0.65))
		i += 2
	return ks[ks.size() - 1]


static func _step(a: Vector3, b: Vector3, s: float, lift: float) -> Vector3:  # 한 걸음: a 에서 b 로 발을 들어 옮김
	return a.lerp(b, smoothstep(0.0, 1.0, s)) + Vector3(0, lift * sin(PI * s), 0)


static func _planted(at: Vector3, pitch: float) -> Vector3:  # 뒤꿈치를 들면 발목이 그만큼 올라감
	return at + Vector3(0, 0.11 * sin(maxf(pitch, 0.0) * PI / 180.0), 0)


func _run_pose(u: float) -> Dictionary:
	var p := Human.stand()
	var pz := lerpf(START_Z, END_Z, smoothstep(0.0, 1.0, u))
	var py := 0.905 - 0.05 * sin(PI * clampf(u / 0.9, 0.0, 1.0)) - 0.02 * smoothstep(0.7, 1.0, u)
	py += 0.012 * sin(PI * clampf(u / 0.3, 0.0, 1.0)) + 0.02 * sin(PI * clampf((u - 0.3) / 0.44, 0.0, 1.0))
	p["pos"] = Vector3(PX, py, pz)
	# 왼발: 서 있다가 → 크게 내디뎌 공 옆에 박음
	var fl: Vector3
	var pl: float
	if u < 0.26:
		pl = 28.0 * smoothstep(0.08, 0.26, u)
		fl = _planted(L0, pl)
	elif u < 0.74:
		var s := (u - 0.26) / 0.48
		pl = lerpf(28.0, -20.0, smoothstep(0.1, 0.9, s))
		fl = _step(_planted(L0, 28.0), L1, s, 0.13)
	else:
		pl = -20.0 * (1.0 - smoothstep(0.74, 0.80, u))
		fl = L1
	# 오른발: 첫 걸음 → 버팀 → 뒤로 젖힘 → 공을 향해 휘두름
	var fr: Vector3
	var pr: float
	if u < 0.30:
		var s := u / 0.30
		pr = lerpf(12.0, -14.0, s) * sin(PI * minf(s * 1.4, 1.0))
		fr = _step(R0, R1, s, 0.09)
	elif u < 0.62:
		pr = 38.0 * smoothstep(0.44, 0.62, u)
		fr = _planted(R1, pr)
	elif u < 0.84:
		var s := (u - 0.62) / 0.22
		pr = lerpf(38.0, 108.0, s)
		fr = _planted(R1, 38.0).lerp(BACK, smoothstep(0.0, 1.0, s))
	else:
		var s := (u - 0.84) / 0.16
		pr = lerpf(108.0, 42.0, s)
		fr = BACK.lerp(HIT, pow(s, 1.5))
		fr.y = lerpf(BACK.y, HIT.y, pow(s, 0.7))
	p["ftL"] = fl
	p["ftR"] = fr
	p["fpL"] = Vector3(pl, 12, 0)
	p["fpR"] = Vector3(pr, 18, 0)
	p["rot"] = _kf(u, [0.0, Vector3(3, 0, 0), 0.25, Vector3(13, 4, 0), 0.62, Vector3(11, -8, -3), 0.84, Vector3(2, -26, -9), 1.0, Vector3(-7, 10, -11)])
	p["spine"] = _kf(u, [0.0, Vector3(4, 0, 0), 0.25, Vector3(8, -8, 0), 0.62, Vector3(8, 8, 0), 0.84, Vector3(-6, 24, 5), 1.0, Vector3(12, -14, 7)])
	p["head"] = _kf(u, [0.0, Vector3(8, 0, 0), 0.5, Vector3(16, 0, 0), 1.0, Vector3(26, 0, 0)])
	p["armL"] = _kf(u, [0.0, Vector3(2, 0, 9), 0.15, Vector3(-32, 0, 12), 0.30, Vector3(-18, 0, 12), 0.52, Vector3(30, 0, 16), 0.74, Vector3(-8, 0, 48), 0.84, Vector3(-28, 0, 88), 1.0, Vector3(14, 0, 66)])
	p["foreL"] = _kf(u, [0.0, Vector3(-14, 0, 0), 0.15, Vector3(-86, 0, 0), 0.52, Vector3(-70, 0, 0), 0.84, Vector3(-22, 0, 0), 1.0, Vector3(-30, 0, 0)])
	p["armR"] = _kf(u, [0.0, Vector3(2, 0, 9), 0.15, Vector3(26, 0, 14), 0.52, Vector3(-34, 0, 12), 0.74, Vector3(8, 0, 26), 0.84, Vector3(40, 0, 34), 1.0, Vector3(-16, 0, 30)])
	p["foreR"] = _kf(u, [0.0, Vector3(-14, 0, 0), 0.15, Vector3(-66, 0, 0), 0.52, Vector3(-88, 0, 0), 0.84, Vector3(-40, 0, 0), 1.0, Vector3(-46, 0, 0)])
	return p


func _follow_pose(v: float) -> Dictionary:  # 찬 뒤 0 → 1: 발이 올라갔다 내려오고 몸은 앞으로 나감
	v = clampf(v, 0.0, 1.0)
	var p := Human.stand()
	var pz := lerpf(END_Z, END_POS.z, 1.0 - (1.0 - v) * (1.0 - v))
	p["pos"] = Vector3(lerpf(PX, END_POS.x, smoothstep(0.1, 1.0, v)), lerpf(0.885, END_POS.y, v) + 0.055 * sin(PI * v), pz)
	var fr: Vector3
	var pr: float
	if v < 0.45:
		var s := v / 0.45
		fr = HIT.lerp(PEAK, 1.0 - (1.0 - s) * (1.0 - s))
		pr = lerpf(42.0, 18.0, s)
	else:
		var s := (v - 0.45) / 0.55
		fr = PEAK.lerp(R2, smoothstep(0.0, 1.0, s))
		pr = lerpf(18.0, 0.0, minf(s * 1.3, 1.0))
	var fl: Vector3
	var pl: float
	if v < 0.35:
		pl = 42.0 * smoothstep(0.0, 0.35, v)
		fl = _planted(L1, pl)
	elif v < 0.92:
		var s := (v - 0.35) / 0.57
		pl = lerpf(42.0, 0.0, s)
		fl = _step(_planted(L1, 42.0), L2, s, 0.06)
	else:
		pl = 0.0
		fl = L2
	p["ftL"] = fl
	p["ftR"] = fr
	p["fpL"] = Vector3(pl, 12, 0)
	p["fpR"] = Vector3(pr, 18, 0)
	p["rot"] = _kf(v, [0.0, Vector3(-7, 10, -11), 0.45, Vector3(-3, 32, -4), 1.0, Vector3(3, 6, 0)])
	p["spine"] = _kf(v, [0.0, Vector3(12, -14, 7), 0.45, Vector3(15, -26, 0), 1.0, Vector3(5, -4, 0)])
	p["head"] = _kf(v, [0.0, Vector3(26, 0, 0), 0.5, Vector3(2, 0, 0), 1.0, Vector3(-4, 0, 0)])
	p["armL"] = _kf(v, [0.0, Vector3(14, 0, 66), 0.45, Vector3(32, 0, 38), 1.0, Vector3(2, 0, 14)])
	p["armR"] = _kf(v, [0.0, Vector3(-16, 0, 30), 0.45, Vector3(-48, 0, 34), 1.0, Vector3(2, 0, 14)])
	p["foreL"] = _kf(v, [0.0, Vector3(-26, 0, 0), 1.0, Vector3(-22, 0, 0)])
	p["foreR"] = _kf(v, [0.0, Vector3(-42, 0, 0), 0.45, Vector3(-30, 0, 0), 1.0, Vector3(-22, 0, 0)])
	return p


func _watch_pose(t: float) -> Dictionary:  # 공을 지켜봄
	var p := _follow_pose(1.0)
	var br := sin(t * 2.4)
	p["pos"] += Vector3(0, 0.004 * br, 0)
	p["spine"] += Vector3(1.2 * br, 0, 0)
	return p


func _react_pose(t: float, result: String, rank: int) -> Dictionary:
	var p := _follow_pose(1.0)
	if result == "goal":
		var jump := (0.03 + 0.035 * rank) * absf(sin(t * 6.4))  # 등급이 높을수록 크게 뜀
		p["pos"] = END_POS + Vector3(0, jump - 0.012, 0)
		p["ftL"] = L2 + Vector3(0, maxf(jump - 0.03, 0.0), 0)
		p["ftR"] = R2 + Vector3(0, maxf(jump - 0.03, 0.0), 0)
		p["rot"] = Vector3(-4, 10.0 * sin(t * 2.1), 0)
		p["spine"] = Vector3(-8, 0, 3.0 * sin(t * 3.2))
		p["head"] = Vector3(-16, 0, 0)
		if rank <= 1:  # 주먹 불끈
			var pump := 0.5 + 0.5 * sin(t * 9.0)
			p["armR"] = Vector3(-72 - 14 * pump, 0, 26)
			p["foreR"] = Vector3(-118 + 30 * pump, 0, 0)
			p["armL"] = Vector3(-24, 0, 16)
			p["foreL"] = Vector3(-84, 0, 0)
			p["twR"] = Vector3(20, 60, 0)
		else:  # 두 팔 번쩍
			var wave := sin(t * 6.4)
			var open := 146.0 + 4.0 * rank
			p["armL"] = Vector3(-12, 0, open + 5.0 * wave)
			p["armR"] = Vector3(-12, 0, open - 5.0 * wave)
			p["foreL"] = Vector3(-20 - 8.0 * wave, 0, 0)
			p["foreR"] = Vector3(-20 + 8.0 * wave, 0, 0)
			p["twL"] = Vector3(70, 10, 0)
			p["twR"] = Vector3(70, 10, 0)
	elif result == "save":  # 머리를 감싸 쥠
		var sway := sin(t * 1.7)
		p["pos"] = END_POS + Vector3(0, -0.02, 0)
		p["rot"] = Vector3(-3, 0, 1.5 * sway)
		p["spine"] = Vector3(-7, 0, 2.0 * sway)
		p["head"] = Vector3(-14 + 3.0 * sway, 0, 0)
		p["armL"] = Vector3(-6, 0, 113)
		p["armR"] = Vector3(-6, 0, 113)
		p["foreL"] = Vector3(-140, 0, 0)
		p["foreR"] = Vector3(-140, 0, 0)
		p["twL"] = Vector3(90, 30, 0)
		p["twR"] = Vector3(90, 30, 0)
	else:  # 빗나감: 어깨가 축 처지고 고개를 떨굼
		var drop := smoothstep(0.0, 0.9, t)
		p["pos"] = END_POS + Vector3(0, -0.03 * drop, 0)
		p["rot"] = Vector3(6, 0, 0)
		p["spine"] = Vector3(10 + 14 * drop, 0, 0)
		p["head"] = Vector3(14 + 24 * drop, 0, 0)
		p["armL"] = Vector3(8, 0, 5)
		p["armR"] = Vector3(8, 0, 5)
		p["foreL"] = Vector3(-6, 0, 0)
		p["foreR"] = Vector3(-6, 0, 0)
	return p


# ---------- 적용 ----------

func _show(p: Dictionary) -> void:
	if human:
		_body.apply(p)
	else:
		_body.apply(_to_puppet(p))


func _to_puppet(p: Dictionary) -> Dictionary:  # 캡슐 인형은 좌우 부호가 실제 방향이고 다리는 각도로만 움직임
	var out := {"pos": p["pos"], "rot": p["rot"], "spine": p["spine"], "head": p["head"]}
	var gp := Basis.from_euler((p["rot"] as Vector3) * PI / 180.0)
	for i in 2:
		var n: String = ["L", "R"][i]
		var sgn := 1.0 if i == 0 else -1.0
		for part in ["arm", "fore"]:
			var v: Vector3 = p[part + n]
			out[part + n] = Vector3(v.x, v.y * sgn, v.z * sgn)
		# 다리: 엉덩이 → 발목 목표를 두 마디로 풂
		var hip: Vector3 = (p["pos"] as Vector3) + gp * Vector3(sgn * 0.10, -0.03, 0)
		var d3: Vector3 = gp.inverse() * ((p["ft" + n] as Vector3) - Vector3(0, 0.03, 0) - hip)
		var l1 := 0.45
		var l2 := 0.40
		var d := clampf(d3.length(), 0.1, (l1 + l2) * 0.999)
		var a1 := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
		var a2 := acos(clampf((l2 * l2 + d * d - l1 * l1) / (2.0 * l2 * d), -1.0, 1.0))
		var fwd := atan2(d3.z, -d3.y)
		out["thigh" + n] = Vector3(-rad_to_deg(fwd + a1), 0, rad_to_deg(atan2(d3.x, sqrt(d3.y * d3.y + d3.z * d3.z))))
		out["shin" + n] = Vector3(rad_to_deg(a1 + a2), 0, 0)
	return out
