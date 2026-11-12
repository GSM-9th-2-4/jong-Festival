extends "res://games/penalty/human.gd"
## 골키퍼(사람 모델). 뼈대/자세 약속은 human.gd 참고. 모델이 없으면 game.gd 가 keeper.gd(캡슐 인형)로 대신함.
## game.gd 가 쓰는 함수는 keeper.gd 와 같음: build / idle / plan / dive / hands / reach_point / land_time.

const STANCE := 0.34   # 준비 자세 발 벌림 (가운데에서, m)

var _side := 0
var _high := 0.5
var _x0 := 0.0
var _keys := []        # [시작, 도약, 뻗기, 착지]


static func ready_to_use() -> bool:
	return available("keeper")


func build() -> bool:
	if not setup("keeper", {"height": 1.86, "kit": Color(0.95, 0.74, 0.06), "gloves": true}):
		return false
	_cur = _base()
	_keys = [_cur, _cur, _cur, _cur]
	_apply(_cur)
	return true


func _base() -> Dictionary:  # 준비 자세: 무릎 굽히고 몸을 앞으로, 두 손은 허리 높이에서 벌림
	var p := stand()
	p.merge({
		"pos": Vector3(0, 0.80, -0.10), "rot": Vector3(10, 0, 0),
		"spine": Vector3(26, 0, 0), "head": Vector3(-30, 0, 0),
		"armL": Vector3(-34, 0, 34), "armR": Vector3(-34, 0, 34),
		"foreL": Vector3(-58, 0, 0), "foreR": Vector3(-58, 0, 0),
		"handL": Vector3(-12, 0, 0), "handR": Vector3(-12, 0, 0),
		"twL": Vector3(25, 45, 0), "twR": Vector3(25, 45, 0),
		"thighL": Vector3(-42, 0, 12), "thighR": Vector3(-42, 0, 12),
		"shinL": Vector3(58, 0, 0), "shinR": Vector3(58, 0, 0),
		"footL": Vector3(-16, 0, 0), "footR": Vector3(-16, 0, 0),
		"ik": Vector3(1, 1, 0),
		"ftL": Vector3(STANCE, ANKLE, 0.0), "ftR": Vector3(-STANCE, ANKLE, 0.0),
		"fpL": Vector3(0, 16, 0), "fpR": Vector3(0, 16, 0),
	}, true)
	return p


func idle(t: float) -> void:
	var p := _base()
	var sw := sin(t * 2.6)
	var bob := absf(cos(t * 2.6))
	p["pos"] += Vector3(0.12 * sw, 0.03 * bob + 0.012 * sin(t * 7.0), 0.01 * sin(t * 3.1))
	p["rot"] += Vector3(1.5 * bob, 3.0 * sw, -3.5 * sw)
	p["spine"] += Vector3(2.0 * sin(t * 5.2), -3.0 * sw, 4.5 * sw)
	p["head"] += Vector3(0, 0, -1.0 * sw)
	var a := sin(t * 5.2)
	var b := sin(t * 5.2 + 0.6)
	p["armL"] += Vector3(3.0 * b, 0, 6.0 * a)
	p["armR"] += Vector3(3.0 * a, 0, 6.0 * b)
	p["foreL"] += Vector3(7.0 * a, 0, 0)
	p["foreR"] += Vector3(7.0 * b, 0, 0)
	_apply(p)


## 다이브 계획. side: -1 왼쪽(-x) / 0 가운데 / +1 오른쪽(+x), high: 0~1
func plan(side: int, high: float) -> void:
	_side = side
	_high = high
	var start := _cur
	_x0 = (start["pos"] as Vector3).x
	var push: Dictionary
	var reach: Dictionary
	var land: Dictionary
	if side == 0:
		if high > 0.5:  # 제자리 점프, 두 손 위로
			push = _base()
			push["pos"] = Vector3(_x0 * 0.5, 0.64, -0.14)
			push["rot"] = Vector3(16, 0, 0)
			push["spine"] = Vector3(32, 0, 0)
			push["armL"] = Vector3(8, 0, 22)
			push["armR"] = Vector3(8, 0, 22)
			push["foreL"] = Vector3(-35, 0, 0)
			push["foreR"] = Vector3(-35, 0, 0)
			reach = _base()
			reach.merge({
				"pos": Vector3(0, 1.08 + 0.22 * high, 0.06), "rot": Vector3(-3, 0, 0),
				"spine": Vector3(-8, 0, 0), "head": Vector3(-12, 0, 0),
				"armL": Vector3(-14, 0, 166), "armR": Vector3(-14, 0, 166),
				"foreL": Vector3(-10, 0, 0), "foreR": Vector3(-10, 0, 0),
				"handL": Vector3(-8, 0, 0), "handR": Vector3(-8, 0, 0),
				"twL": Vector3(85, 5, 0), "twR": Vector3(85, 5, 0),
				"thighL": Vector3(-6, 0, 7), "thighR": Vector3(-18, 0, 6),
				"shinL": Vector3(14, 0, 0), "shinR": Vector3(38, 0, 0),
				"footL": Vector3(40, 0, 0), "footR": Vector3(34, 0, 0),
				"ik": Vector3(0, 0, 0),
			}, true)
			land = _base()
			land["pos"] = Vector3(0, 0.74, -0.08)
			land["armL"] = Vector3(-30, 0, 55)
			land["armR"] = Vector3(-30, 0, 55)
		else:  # 낮게 웅크려 몸으로 막기
			push = _base()
			push["pos"] = Vector3(_x0 * 0.5, 0.74, -0.10)
			reach = _base()
			reach.merge({
				"pos": Vector3(0, 0.54, -0.10), "rot": Vector3(8, 0, 0),
				"spine": Vector3(34, 0, 0), "head": Vector3(-34, 0, 0),
				"armL": Vector3(-36, 0, -15), "armR": Vector3(-36, 0, -15),
				"foreL": Vector3(-16, 0, 0), "foreR": Vector3(-16, 0, 0),
				"handL": Vector3(-25, 0, 0), "handR": Vector3(-25, 0, 0),
				"twL": Vector3(60, 40, 0), "twR": Vector3(60, 40, 0),
			}, true)
			land = reach.duplicate()
			land["pos"] = Vector3(0, 0.50, -0.10)
	else:
		# +x 쪽(lead = L)으로 뛰는 자세를 만들고, 반대쪽이면 뒤집음
		var ang := lerpf(80.0, 50.0, high)
		var yy := lerpf(0.50, 1.30, high)
		var xx := lerpf(1.70, 1.42, high)
		var x0 := _x0 * float(side)
		push = _base()
		push.merge({
			"pos": Vector3(x0 + 0.40, 0.72, -0.04), "rot": Vector3(8, -6, -22),
			"spine": Vector3(16, 0, -8), "head": Vector3(-18, 0, 10),
			"armL": Vector3(-38, 0, 78), "armR": Vector3(-46, 0, 14),
			"foreL": Vector3(-42, 0, 0), "foreR": Vector3(-62, 0, 0),
			"twL": Vector3(50, 30, 0), "twR": Vector3(35, 40, 0),
			"ftL": Vector3(STANCE + 0.26, ANKLE, 0.06),
		}, true)
		reach = _base()
		reach.merge({
			"pos": Vector3(xx, yy, 0.22), "rot": Vector3(-2, -8, -ang),
			"spine": Vector3(-8, 0, -10), "head": Vector3(-6, 0, -10),
			"armL": Vector3(-14, 0, 168), "armR": Vector3(-26, 0, 172),
			"foreL": Vector3(-6, 0, 0), "foreR": Vector3(-14, 0, 0),
			"handL": Vector3(-6, 0, 0), "handR": Vector3(-6, 0, 0),
			"twL": Vector3(85, 5, 0), "twR": Vector3(80, 5, 0),
			"thighL": Vector3(-4, 0, 5), "thighR": Vector3(-38, 0, 16),
			"shinL": Vector3(10, 0, 0), "shinR": Vector3(66, 0, 0),
			"footL": Vector3(42, 0, 0), "footR": Vector3(30, 0, 0),
			"ik": Vector3(0, 0, 0),
		}, true)
		land = _base()
		land.merge({
			"pos": Vector3(xx + 0.50, 0.25, 0.28), "rot": Vector3(10, -6, -86),
			"spine": Vector3(12, 0, 12), "head": Vector3(-14, 0, 18),
			"armL": Vector3(-30, 0, 158), "armR": Vector3(-62, 0, 92),
			"foreL": Vector3(-34, 0, 0), "foreR": Vector3(-52, 0, 0),
			"handL": Vector3(-6, 0, 0), "handR": Vector3(-10, 0, 0),
			"twL": Vector3(70, 10, 0), "twR": Vector3(40, 30, 0),
			"thighL": Vector3(-12, 0, 2), "thighR": Vector3(-48, 0, 8),
			"shinL": Vector3(26, 0, 0), "shinR": Vector3(74, 0, 0),
			"footL": Vector3(30, 0, 0), "footR": Vector3(20, 0, 0),
			"ik": Vector3(0, 0, 0),
		}, true)
		if side < 0:
			push = _mirror(push)
			reach = _mirror(reach)
			land = _mirror(land)
	_keys = [start, push, reach, land]


func _dive_pose(k: float, l: float) -> Dictionary:
	var p: Dictionary
	if l <= 0.0:
		if k < 0.34:
			p = _blend(_keys[0], _keys[1], smoothstep(0.0, 1.0, k / 0.34))
		else:
			var u := (k - 0.34) / 0.66
			p = _blend(_keys[1], _keys[2], 1.0 - pow(1.0 - u, 1.7))
			# 몸은 포물선으로 뜸
			p["pos"] = (p["pos"] as Vector3) + Vector3(0, 0.10 * sin(u * PI) * (1.0 if _side != 0 else 0.3), 0)
			# 발은 땅을 박차고 금방 떨어짐
			if (_keys[2]["ik"] as Vector3).x < 0.5:
				p["ik"] = (_keys[1]["ik"] as Vector3) * clampf(1.0 - u * 3.2, 0.0, 1.0)
	else:
		p = _blend(_keys[2], _keys[3], smoothstep(0.0, 1.0, l))
		var pos: Vector3 = p["pos"]
		pos.y = lerpf(_keys[2]["pos"].y, _keys[3]["pos"].y, minf(l * l * 1.6, 1.0))
		if l > 0.62:  # 착지 후 살짝 튕김
			pos.y += 0.035 * sin((l - 0.62) / 0.38 * PI)
		p["pos"] = pos
		if (_keys[3]["ik"] as Vector3).x > 0.5 and (_keys[2]["ik"] as Vector3).x < 0.5:
			p["ik"] = Vector3.ONE * smoothstep(0.35, 0.8, l)  # 점프 뒤 발이 다시 땅에
	return p


## k: 0(차는 순간) → 1(공이 도착, 최대로 뻗음),  l: 0 → 1 (착지)
func dive(k: float, l: float) -> void:
	_apply(_dive_pose(k, l))


func _hands_local() -> Vector3:
	var a := _g[_b["Bip01 L Hand"]]
	var b := _g[_b["Bip01 R Hand"]]
	return (a.origin + a.basis.x * 0.10 + b.origin + b.basis.x * 0.10) * 0.5


func hands() -> Vector3:  ## 두 장갑의 가운데 (월드 좌표)
	return _skel.global_transform * _hands_local()


func reach_point() -> Vector3:  ## 최대로 뻗었을 때 손 위치 (현재 자세는 유지)
	_solve(_dive_pose(1.0, 0.0))
	var h := hands()
	_solve(_cur)
	return h


func land_time() -> float:
	return 0.55 if _side != 0 else 0.45
