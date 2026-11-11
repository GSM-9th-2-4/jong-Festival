extends RefCounted
## 펀치머신용 도형 도구: 모서리가 둥근 상자, 회전체(샌드백), 곡선 다듬기.
## UV 는 미터 단위 → 재질의 uv1_scale = "1m 에 무늬 몇 번".


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, idx: Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array(idx)
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	st.generate_tangents()
	return st.commit()


static func _tri(idx: Array, verts: PackedVector3Array, normals: PackedVector3Array, a: int, b: int, c: int) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(normals[a] + normals[b] + normals[c]) > 0.0:  # Godot 앞면 = 시계 방향
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


static func _coords(h: float, r: float, seg: int) -> Array:
	var inner := h - r
	var out := []
	for i in seg:
		out.append(-inner - r * tan(PI / 4.0 * (seg - i) / seg))
	out.append(-inner)
	out.append(inner)
	for i in range(1, seg + 1):
		out.append(inner + r * tan(PI / 4.0 * i / seg))
	return out


## 모서리가 둥근 상자 (가운데가 원점).
static func rbox(size: Vector3, r := 0.02, seg := 3) -> ArrayMesh:
	var h := size * 0.5
	r = clampf(r, 0.0005, minf(h.x, minf(h.y, h.z)) - 0.0002)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := []
	for ax in [[0, 1, 2], [2, 1, 0], [0, 2, 1]]:
		var cu := _coords(h[ax[0]], r, seg)
		var cv := _coords(h[ax[1]], r, seg)
		for s in [-1.0, 1.0]:
			var base := verts.size()
			for b in cv:
				for a in cu:
					var p := Vector3.ZERO
					p[ax[0]] = a
					p[ax[1]] = b
					p[ax[2]] = s * h[ax[2]]
					var inner := Vector3(clampf(p.x, -(h.x - r), h.x - r), clampf(p.y, -(h.y - r), h.y - r), clampf(p.z, -(h.z - r), h.z - r))
					var n := (p - inner).normalized()
					verts.append(inner + n * r)
					normals.append(n)
					uvs.append(Vector2(a + h[ax[0]], h[ax[1]] - b))
			var w := cu.size()
			for j in cv.size() - 1:
				for i in w - 1:
					var q := base + j * w + i
					_tri(idx, verts, normals, q, q + 1, q + w + 1)
					_tri(idx, verts, normals, q, q + w + 1, q + w)
	return _commit(verts, normals, uvs, idx)


## 곡선 다듬기 (Catmull-Rom). profile: (반지름, 높이) 점들.
static func smooth(profile: Array, sub := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := profile.size()
	for i in n - 1:
		var p0: Vector2 = profile[maxi(i - 1, 0)]
		var p1: Vector2 = profile[i]
		var p2: Vector2 = profile[i + 1]
		var p3: Vector2 = profile[mini(i + 2, n - 1)]
		for k in sub:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(k) / sub))
	out.append(profile[n - 1])
	return out


## 회전체. profile 은 아래→위 순서의 (반지름, 높이). a0~a1 각도만 만들 수도 있음(박음질 띠). push: 바깥으로 띄우기.
static func lathe(profile: PackedVector2Array, segs := 40, a0 := 0.0, a1 := TAU, push := 0.0) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := []
	var n := profile.size()
	var v := 0.0
	var rmax := 0.0
	for p in profile:
		rmax = maxf(rmax, p.x)
	for i in n:
		var t: Vector2 = profile[mini(i + 1, n - 1)] - profile[maxi(i - 1, 0)]
		var n2 := Vector2(t.y, -t.x).normalized()
		if i > 0:
			v += profile[i].distance_to(profile[i - 1])
		for j in segs + 1:
			var ang := lerpf(a0, a1, float(j) / segs)
			var dir := Vector3(cos(ang), 0, sin(ang))
			var nrm := (dir * n2.x + Vector3.UP * n2.y).normalized()
			verts.append(dir * profile[i].x + Vector3.UP * profile[i].y + nrm * push)
			normals.append(nrm)
			uvs.append(Vector2(ang * rmax, -v))
	var w := segs + 1
	for i in n - 1:
		for j in segs:
			var q := i * w + j
			_tri(idx, verts, normals, q, q + 1, q + w + 1)
			_tri(idx, verts, normals, q, q + w + 1, q + w)
	return _commit(verts, normals, uvs, idx)


## 얇은 선(금 간 유리 등)을 평면 위 띠로. lines: [[Vector2...], ...], z 고정.
static func strips(lines: Array, width := 0.002) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for line in lines:
		var m: int = line.size()
		for i in m - 1:
			var a: Vector2 = line[i]
			var b: Vector2 = line[i + 1]
			var wa := width * (1.0 - float(i) / m)
			var wb := width * (1.0 - float(i + 1) / m)
			var nn := (b - a).orthogonal().normalized()
			var p := [a + nn * wa, a - nn * wa, b - nn * wb, b + nn * wb]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(0, 0, 1))
				st.add_vertex(Vector3(p[k].x, p[k].y, 0))
	return st.commit()
