class_name Island
extends RefCounted

## The whole world is one island: a procedural height field with an irregular
## coastline, bays, lakes, rolling hills and a mountain spine.  Sea level is 0,
## so anything with a negative height is under water.
##
## The height field is baked once at start up into a regular grid.  Cities and
## roads are flattened into it during that bake, so the terrain, the road
## ribbons and the physics collider all agree with each other.

const HALF := 4300.0          ## terrain covers -HALF..+HALF on both axes
const RES := 18.0             ## metres between two height samples
const SEA := 0.0
const SHORE := 1.6            ## beach band above sea level

var size := 0                 ## samples per side
var heights := PackedFloat32Array()
var seed_value := 20261101

var _n_coast: FastNoiseLite
var _n_hill: FastNoiseLite
var _n_mount: FastNoiseLite
var _n_crag: FastNoiseLite
var _n_detail: FastNoiseLite
var _ready := false
var river_polys: Array = []   # PackedVector2Array per river
var river_levels: Array = []  # PackedFloat32Array, water surface height per point
var bank := PackedFloat32Array()   ## per grid node: how close to a river bank (0..1)
const RIVER_R := 78.0   ## half width of the carved river valley
const RIVER_W := 54.0   ## width of the water ribbon
const RIVER_DROP := 3.4 ## how far the water sits below the bank

## Flowing water: two scrolling sine fields drive the colour and the roughness,
## so the rivers shimmer and drift without a single texture.
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.09, 0.33, 0.48);
uniform vec3 shallow : source_color = vec3(0.30, 0.68, 0.82);
uniform float alpha : hint_range(0.0, 1.0) = 0.88;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * 0.55;
	float w = sin(wp.x * 0.42 + t) * 0.5 + sin(wp.z * 0.53 - t * 1.25) * 0.5;
	float w2 = sin((wp.x + wp.z) * 1.35 + t * 1.9) * 0.5 + 0.5;
	float w3 = cos((wp.x - wp.z) * 2.6 - t * 2.4) * 0.5 + 0.5;
	float k = clamp(0.42 + w * 0.30 + w2 * 0.20 + w3 * 0.08, 0.0, 1.0);
	vec3 c = mix(deep, shallow, k);
	ALBEDO = c;
	ALPHA = alpha;
	ROUGHNESS = 0.06 + w2 * 0.10;
	METALLIC = 0.30;
	SPECULAR = 0.85;
	EMISSION = c * 0.06;
}
"""

func _init(p_seed: int = 20261101) -> void:
	seed_value = p_seed
	size = int(round(HALF * 2.0 / RES)) + 1
	_build_noise()

func _build_noise() -> void:
	_n_coast = FastNoiseLite.new()
	_n_coast.seed = seed_value
	_n_coast.frequency = 0.00045
	_n_coast.fractal_octaves = 4
	_n_coast.fractal_lacunarity = 2.1

	_n_hill = FastNoiseLite.new()
	_n_hill.seed = seed_value + 991
	_n_hill.frequency = 0.0009
	_n_hill.fractal_octaves = 3

	_n_mount = FastNoiseLite.new()
	_n_mount.seed = seed_value + 4417
	_n_mount.frequency = 0.00042
	_n_mount.fractal_octaves = 4
	_n_mount.fractal_type = FastNoiseLite.FRACTAL_RIDGED

	# crags: the high frequency ridged noise that gives the mountains their
	# broken rock faces instead of one smooth cone
	_n_crag = FastNoiseLite.new()
	_n_crag.seed = seed_value + 13
	_n_crag.frequency = 0.0021
	_n_crag.fractal_octaves = 3
	_n_crag.fractal_type = FastNoiseLite.FRACTAL_RIDGED

	_n_detail = FastNoiseLite.new()
	_n_detail.seed = seed_value + 77
	_n_detail.frequency = 0.006
	_n_detail.fractal_octaves = 2

# ------------------------------------------------------------------ sampling

## Raw, un-flattened terrain height.
func raw_height(x: float, z: float) -> float:
	var d := sqrt(x * x + z * z) / (HALF * 0.80)
	var coast := _n_coast.get_noise_2d(x, z)
	# irregular, lobed coastline
	var radial := 1.0 - smoothstep(0.34, 1.02, d + coast * 0.20)
	if radial <= 0.0:
		return -22.0 - absf(coast) * 8.0
	# mountain spine down the middle of the island
	var spine := absf(z + sin(x * 0.0006) * 900.0) / 2100.0
	var mount := clampf(1.0 - spine, 0.0, 1.0)
	mount = pow(mount, 2.2) * pow(radial, 1.4)
	var ridge := _n_mount.get_noise_2d(x, z) * 0.5 + 0.5
	var h := -18.0 + radial * 44.0
	h += radial * _n_hill.get_noise_2d(x, z) * 26.0
	h += mount * (64.0 + ridge * 214.0)
	# crags + gullies carved into the flanks
	var crag := _n_crag.get_noise_2d(x, z) * 0.5 + 0.5
	h += mount * (crag - 0.5) * 52.0 * (0.30 + mount * 0.95)
	var gully := _n_crag.get_noise_2d(x * 2.3 + 800.0, z * 2.3 - 500.0) * 0.5 + 0.5
	h -= mount * gully * 11.0
	h += radial * _n_detail.get_noise_2d(x, z) * 3.5
	return h

## Trace a handful of rivers down the hillsides and cut a shallow channel for
## each one, then give every river its own water ribbon that follows the slope
## (the ocean plane only fills what is below sea level, so creeks in the hills
## need their own surface).
func _carve_rivers(plateaus: Array) -> void:
	river_polys.clear()
	river_levels.clear()
	bank.resize(size * size)
	for i in bank.size():
		bank[i] = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 313
	var tries := 0
	while river_polys.size() < 9 and tries < 2000:
		tries += 1
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(HALF * 0.10, HALF * 0.50)
		var p := Vector2(cos(ang), sin(ang)) * rad
		var h0 := raw_height(p.x, p.y)
		if h0 < 4.0 or h0 > 78.0:
			continue
		var pts := PackedVector2Array()
		for step in 260:
			pts.append(p)
			var best := p
			var best_h := raw_height(p.x, p.y)
			for k in 12:
				var a := TAU * float(k) / 12.0
				var q := p + Vector2(cos(a), sin(a)) * 52.0
				var hh := raw_height(q.x, q.y) + rng.randf_range(-1.2, 1.2)
				if hh < best_h:
					best_h = hh
					best = q
			if best == p:
				break
			p = best
			if best_h < 1.0 or absf(p.x) > HALF - 80.0 or absf(p.y) > HALF - 80.0:
				break
			var near_town := false
			for pl in plateaus:
				if p.distance_to(pl["c"]) < float(pl["r"]) + 110.0:
					near_town = true
					break
			if near_town:
				break
		if pts.size() < 12:
			continue
		# water level: always descending, a few metres below the local bank
		var lv := PackedFloat32Array()
		var prev := 1e9
		for q in pts:
			var l := minf(prev, raw_height(q.x, q.y) - RIVER_DROP)
			lv.append(l)
			prev = l
		river_polys.append(pts)
		river_levels.append(lv)
		# cut the channel
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var la: float = lv[i]
			var lb: float = lv[i + 1]
			var seg := a.distance_to(b)
			var n := maxi(1, int(seg / 12.0))
			for k in n + 1:
				var t := float(k) / float(n)
				var c := a.lerp(b, t)
				var bed := lerpf(la, lb, t) - 2.6
				var ci := int((c.x + HALF) / RES)
				var cj := int((c.y + HALF) / RES)
				var span := int(ceil(RIVER_R / RES)) + 1
				for dj in range(-span, span + 1):
					var j := cj + dj
					if j < 0 or j >= size:
						continue
					var z := -HALF + float(j) * RES
					for di in range(-span, span + 1):
						var ii := ci + di
						if ii < 0 or ii >= size:
							continue
						var x := -HALF + float(ii) * RES
						var d := Vector2(x, z).distance_to(c)
						if d > RIVER_R:
							continue
						var w := pow(1.0 - smoothstep(0.35 * RIVER_R, RIVER_R, d), 1.7)
						var idx := j * size + ii
						heights[idx] = minf(heights[idx], lerpf(heights[idx], bed, w))
						if w > 0.12:
							bank[idx] = maxf(bank[idx], w)

## Water ribbon mesh for every river (built once, lives in the world).
func build_river_mesh() -> MeshInstance3D:
	var b := MeshBatch.new()
	for ri in river_polys.size():
		var pts: PackedVector2Array = river_polys[ri]
		var lv: PackedFloat32Array = river_levels[ri]
		for i in pts.size() - 1:
			var a := pts[i]
			var c := pts[i + 1]
			var dir := (c - a)
			if dir.length() < 0.01:
				continue
			var nrm := Vector2(-dir.y, dir.x).normalized() * (RIVER_W * 0.5)
			var ya: float = lv[i] + 0.55
			var yc: float = lv[i + 1] + 0.55
			var p0 := Vector3(a.x - nrm.x, ya, a.y - nrm.y)
			var p1 := Vector3(a.x + nrm.x, ya, a.y + nrm.y)
			var p2 := Vector3(c.x + nrm.x, yc, c.y + nrm.y)
			var p3 := Vector3(c.x - nrm.x, yc, c.y - nrm.y)
			b.quad(MeshBatch.SOLID, p0, p1, p2, p3, CityConfig.C_WATER, Vector3.UP)
	if b.is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Rivers"
	mi.mesh = b.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mi.material_override = mat
	return mi

func is_land(x: float, z: float) -> bool:
	return raw_height(x, z) > SHORE + 1.5

# ------------------------------------------------------------------ bake

## Bake the final height grid.  `plateaus` are [center: Vector2, radius: float,
## height: float] (cities) and `road_pts` are [pos: Vector3, radius: float]
## (flattened corridors).  Call this once, before building meshes.
func bake(plateaus: Array, road_pts: Array) -> void:
	heights.resize(size * size)
	# 1) raw terrain
	for j in size:
		var z := -HALF + float(j) * RES
		for i in size:
			var x := -HALF + float(i) * RES
			heights[j * size + i] = raw_height(x, z)
	# 1b) rivers carved out of the raw terrain, so towns and roads flatten on top
	_carve_rivers(plateaus)
	# 2) city plateaus
	for p in plateaus:
		var pc: Vector2 = p["c"]
		var pr: float = p["r"] + 130.0
		var ph: float = p["h"]
		var i0 := clampi(int((pc.x - pr + HALF) / RES), 0, size - 1)
		var i1 := clampi(int((pc.x + pr + HALF) / RES), 0, size - 1)
		var j0 := clampi(int((pc.y - pr + HALF) / RES), 0, size - 1)
		var j1 := clampi(int((pc.y + pr + HALF) / RES), 0, size - 1)
		for j in range(j0, j1 + 1):
			var z := -HALF + float(j) * RES
			for i in range(i0, i1 + 1):
				var x := -HALF + float(i) * RES
				var dist := Vector2(x, z).distance_to(pc)
				var w := 1.0 - smoothstep(p["r"], pr, dist)
				if w <= 0.0:
					continue
				var idx := j * size + i
				heights[idx] = lerpf(heights[idx], ph, w)
	# 3) road corridors, flattened towards their own centreline height
	for rp in road_pts:
		var pos: Vector3 = rp["p"]
		var r: float = rp["r"]
		var i0 := clampi(int((pos.x - r + HALF) / RES), 0, size - 1)
		var i1 := clampi(int((pos.x + r + HALF) / RES), 0, size - 1)
		var j0 := clampi(int((pos.z - r + HALF) / RES), 0, size - 1)
		var j1 := clampi(int((pos.z + r + HALF) / RES), 0, size - 1)
		for j in range(j0, j1 + 1):
			var z := -HALF + float(j) * RES
			for i in range(i0, i1 + 1):
				var x := -HALF + float(i) * RES
				var dist := Vector2(x, z).distance_to(Vector2(pos.x, pos.z))
				if dist > r:
					continue
				var w := 1.0 - smoothstep(r * 0.55, r, dist)
				var idx := j * size + i
				heights[idx] = lerpf(heights[idx], pos.y, w * 0.94)
	_ready = true

func baked() -> bool:
	return _ready

## Bilinear height lookup from the baked grid (metres).
func height(x: float, z: float) -> float:
	if not _ready:
		return raw_height(x, z)
	var fx := (x + HALF) / RES
	var fz := (z + HALF) / RES
	var i := clampi(int(floor(fx)), 0, size - 2)
	var j := clampi(int(floor(fz)), 0, size - 2)
	var tx := clampf(fx - float(i), 0.0, 1.0)
	var tz := clampf(fz - float(j), 0.0, 1.0)
	var h00 := heights[j * size + i]
	var h10 := heights[j * size + i + 1]
	var h01 := heights[(j + 1) * size + i]
	var h11 := heights[(j + 1) * size + i + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func normal_at(x: float, z: float) -> Vector3:
	var e := 2.0
	var hx := height(x + e, z) - height(x - e, z)
	var hz := height(x, z + e) - height(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()

func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y

# ------------------------------------------------------------------ meshes

func build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(size * size)
	norms.resize(size * size)
	cols.resize(size * size)
	for j in size:
		var z := -HALF + float(j) * RES
		for i in size:
			var x := -HALF + float(i) * RES
			var k := j * size + i
			var h := heights[k]
			verts[k] = Vector3(x, h, z)
			norms[k] = normal_at(x, z)
			cols[k] = _terrain_color(x, z, h)
	var quads := (size - 1) * (size - 1)
	idx.resize(quads * 6)
	var w := 0
	for j in size - 1:
		for i in size - 1:
			var a := j * size + i
			var b := a + 1
			var c := a + size
			var d := c + 1
			idx[w] = a
			idx[w + 1] = c
			idx[w + 2] = b
			idx[w + 3] = b
			idx[w + 4] = c
			idx[w + 5] = d
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# the terrain is painted with vertex colours, so it needs the same vertex
	# colour material the rest of the world uses
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.vertex_color_is_srgb = true
	tmat.roughness = 0.95
	tmat.metallic = 0.0
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# a procedural grain multiply, triplanar projected, so grass and rock are not
	# flat slabs of colour when you look at them from two metres away
	var grain := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.seed = 5150
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.055
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 4
	grain.noise = fn
	grain.width = 512
	grain.height = 512
	grain.seamless = true
	grain.generate_mipmaps = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.74, 0.74, 0.74))
	ramp.set_color(1, Color(1.16, 1.16, 1.16))
	ramp.add_point(0.55, Color(0.95, 0.95, 0.95))
	grain.color_ramp = ramp
	tmat.albedo_texture = grain
	tmat.uv1_triplanar = true
	tmat.uv1_scale = Vector3(0.085, 0.085, 0.085)
	tmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mesh.surface_set_material(0, tmat)
	return mesh

## Vertex colour of the terrain: beaches, mud banks along the rivers, layered
## grass, exposed rock strata on the steep faces, scree at altitude and a dappled
## snow line.  This is what gives the mountains their detail — there is no
## texture anywhere in the project.
func _terrain_color(x: float, z: float, h: float) -> Color:
	var n := _n_detail.get_noise_2d(x, z)
	var n2 := _n_detail.get_noise_2d(x * 4.1 + 700.0, z * 4.1 - 300.0)
	var grain := _n_detail.get_noise_2d(x * 9.0, z * 9.0)
	var slope := slope_at(x, z)
	if h < -2.0:
		return Color("2f6f86").lerp(Color("1e4f66"), clampf(-h / 20.0, 0.0, 1.0))
	# river bank: wet mud and sand either side of the channel
	var bi := 0
	var gi := int((x + HALF) / RES)
	var gj := int((z + HALF) / RES)
	if gi >= 0 and gi < size and gj >= 0 and gj < size:
		bi = gj * size + gi
	if bi > 0 and bank[bi] > 0.15 and h > -3.0:
		var b := clampf(bank[bi], 0.0, 1.0)
		var wet := Color("8a7d63").lerp(Color("6f6752"), clampf(0.5 + grain * 0.5, 0.0, 1.0))
		return wet.lerp(Color("d9c79a"), clampf(1.0 - b * 1.6, 0.0, 1.0))
	if h < SHORE + 1.2:
		var sand := Color("d9c79a").lerp(Color("c8b288"), clampf(grain * 0.5 + 0.5, 0.0, 1.0))
		if h < SHORE - 0.4:
			sand = sand.lerp(Color("b7a374"), 0.5)
		return sand
	# ---- grass from the coast all the way up to the alpine meadow
	var grass := Color("47702f").lerp(Color("6f9a44"), clampf(n * 0.5 + 0.5, 0.0, 1.0))
	grass = grass.lerp(Color("8aa654"), clampf(n2 * 0.5 + 0.5, 0.0, 1.0) * 0.35)
	if h > 95.0:
		grass = grass.lerp(Color("5d7444"), clampf((h - 95.0) / 110.0, 0.0, 1.0))
	if h < 12.0:
		grass = grass.lerp(Color("86a055"), clampf((12.0 - h) / 14.0, 0.0, 1.0) * 0.3)
	# ---- rock: steep faces are bare, and the tops shed their soil
	var rockiness := clampf((slope - 0.26) / 0.34, 0.0, 1.0)
	rockiness = maxf(rockiness, clampf((h - 200.0) / 70.0, 0.0, 1.0) * 0.8)
	var band := 0.5 + 0.5 * sin(h * 0.55 + n * 3.0)
	var rock := Color("7d7568").lerp(Color("57534c"), band)
	rock = rock.lerp(Color("a09a8e"), clampf(n2 * 0.5 + 0.5, 0.0, 1.0) * 0.40)
	grass = grass.lerp(rock, rockiness)
	# scree fields just under the snow
	if h > 232.0:
		grass = grass.lerp(Color("aaa49a"), clampf((h - 232.0) / 34.0, 0.0, 1.0) * 0.55)
	# ---- snow: noisy edge, blue in the hollows, rock still poking through
	var snow_line := 254.0 + n * 24.0 + grain * 5.0
	if h > snow_line:
		var k := clampf((h - snow_line) / 24.0, 0.0, 1.0)
		var snow := Color("f4f8fb").lerp(Color("ccd8e6"), clampf(0.55 - n * 0.5, 0.0, 1.0))
		if slope > 0.42:
			# snow will not lie on a cliff
			k *= 0.45
		if slope < 0.22:
			snow = snow.lerp(Color("e2ecf4"), 0.45)
		grass = snow.lerp(grass, 1.0 - k)
	return grass
