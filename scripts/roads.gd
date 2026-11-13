class_name RoadNet
extends RefCounted

## Where the cities are and how the roads get between them.
##
## Eighteen towns are dropped onto the island at random spots that pass a few
## tests (on land, not on a beach, not too steep, far enough apart).  They are
## then wired together with a minimum spanning tree plus a couple of extra
## links, and every link becomes a winding road: the straight line is pushed
## sideways by smooth noise, the height follows the island and is smoothed
## along the way.  City streets are the local block grid (see CityConfig), so a
## town is a few hundred metres of proper streets, not part of a world grid.

const NAMES := [
	"PEAK", "CLOCK TOWER", "FACTORY", "HANGAR", "MILL", "SHIPYARD",
	"OBSERVATORY", "CAPE TOWN", "SENTOSA", "POCHINOK", "MARS ELECTRIC",
	"RIM NAM VILLAGE", "KATULISTIWA", "BIMASAKTI STRIP", "BULLSEYE",
	"GRAVEYARD", "PLANTATION", "RIVERSIDE",
]

const KINDS := [
	CityWorld.KIND_NATURE, CityWorld.KIND_TOWN, CityWorld.KIND_INDUSTRIAL,
	CityWorld.KIND_INDUSTRIAL, CityWorld.KIND_INDUSTRIAL, CityWorld.KIND_INDUSTRIAL,
	CityWorld.KIND_NATURE, CityWorld.KIND_RURAL, CityWorld.KIND_NEON,
	CityWorld.KIND_RURAL, CityWorld.KIND_INDUSTRIAL, CityWorld.KIND_RURAL,
	CityWorld.KIND_RURAL, CityWorld.KIND_NEON, CityWorld.KIND_INDUSTRIAL,
	CityWorld.KIND_NATURE, CityWorld.KIND_RURAL, CityWorld.KIND_TOWN,
]

const LANDMARKS := [
	CityBuilder.PEAK, CityBuilder.CLOCKTOWER, CityBuilder.FACTORY,
	CityBuilder.HANGAR, CityBuilder.MILL, CityBuilder.SHIPYARD,
	CityBuilder.OBSERVATORY, CityBuilder.CAPETOWN, CityBuilder.SENTOSA,
	CityBuilder.POCHINOK, CityBuilder.MARSELECTRIC, CityBuilder.RIMNAM,
	CityBuilder.KATULISTIWA, CityBuilder.BIMASAKTI, CityBuilder.BULLSEYE,
	CityBuilder.GRAVEYARD, CityBuilder.PLANTATION, CityBuilder.RIVERSIDE,
]

var island: Island
var cities: Array = []        ## {name, kind, landmark, c: Vector2, h, blocks, r}
var links: Array = []         ## Array of Array[Vector3] (road centreline)
var samples: Array = []       ## Vector3, every ~9 m along every road
var road_cells: Dictionary = {}   ## Vector2i cell (24 m) -> true, for fast "is this on a road"

var street_cars: Array = []   ## {pos: Vector3, yaw: float} parking spots

func generate(isl: Island, p_seed: int = 7) -> void:
	island = isl
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	_place_cities(rng)
	_link_cities(rng)
	_sample_roads()
	_index_roads()
	_parking(rng)

# ------------------------------------------------------------------ cities

func _place_cities(rng: RandomNumberGenerator) -> void:
	# Jittered rings: four towns in the middle of the island, six around them and
	# eight out towards the coast.  Each one then hunts for a bit of flat land
	# nearby, so the layout is different every seed but always spread out.
	cities.clear()
	var rings := [
		{"rad": 0.30, "count": 4},
		{"rad": 0.64, "count": 6},
		{"rad": 0.98, "count": 8},
	]
	var idx := 0
	for ring in rings:
		var count: int = ring["count"]
		var base := rng.randf() * TAU
		for k in count:
			var ang := base + TAU * (float(k) + rng.randf_range(-0.28, 0.28)) / float(count)
			var rad := Island.HALF * 0.62 * (float(ring["rad"]) + rng.randf_range(-0.06, 0.06))
			var best := Vector2(cos(ang), sin(ang)) * rad
			var best_h := island.raw_height(best.x, best.y)
			for attempt in 90:
				var a2 := ang + rng.randf_range(-0.10, 0.10)
				var r2 := rad * rng.randf_range(0.86, 1.14)
				var cand := Vector2(cos(a2), sin(a2)) * r2
				var hh := island.raw_height(cand.x, cand.y)
				if hh < 5.0 or island.slope_at(cand.x, cand.y) > 0.30:
					continue
				var clear := true
				for other in cities:
					if cand.distance_to(other["c"]) < 1000.0:
						clear = false
						break
				if not clear:
					continue
				best = cand
				best_h = hh
				break
			var n := rng.randi_range(4, 6)
			cities.append({
				"name": NAMES[idx],
				"kind": KINDS[idx],
				"landmark": LANDMARKS[idx],
				"c": best,
				"h": maxf(best_h, 6.0) - 0.6,
				"blocks": n,
				"r": float(n) * CityConfig.CELL * 0.5 + 26.0,
				"seed": rng.randi(),
			})
			idx += 1

func city_radius(ci: int) -> float:
	return float(cities[ci]["r"])

## Centre of one block of one city (world space, on the city plateau).
func block_center(ci: int, bx: int, bz: int) -> Vector3:
	var c: Dictionary = cities[ci]
	var n: float = float(c["blocks"])
	var half := (n - 1.0) * 0.5
	return Vector3(
		float(c["c"].x) + (float(bx) - half) * CityConfig.CELL,
		float(c["h"]),
		float(c["c"].y) + (float(bz) - half) * CityConfig.CELL)

func city_at_point(p: Vector3) -> int:
	for i in cities.size():
		var c: Dictionary = cities[i]
		var d := Vector2(p.x, p.z).distance_to(c["c"])
		if d < float(c["r"]) + 30.0:
			return i
	return -1

func city_name_at(p: Vector3) -> String:
	var i := city_at_point(p)
	return "" if i < 0 else String(cities[i]["name"])

## Closest city centre (for spawning and for the map).
func nearest_city(p: Vector3) -> int:
	var best := -1
	var bd := 1.0e18
	for i in cities.size():
		var c: Dictionary = cities[i]
		var d := Vector2(p.x, p.z).distance_squared_to(c["c"])
		if d < bd:
			bd = d
			best = i
	return best

# ------------------------------------------------------------------ roads

func _link_cities(rng: RandomNumberGenerator) -> void:
	links.clear()
	if cities.size() < 2:
		return
	# Prim: minimum spanning tree over the city centres
	var in_tree := {0: true}
	var edges: Array = []
	while in_tree.size() < cities.size():
		var best_a := -1
		var best_b := -1
		var best_d := 1.0e18
		for a in in_tree.keys():
			for b in cities.size():
				if in_tree.has(b):
					continue
				var d: float = (cities[a]["c"] as Vector2).distance_to(cities[b]["c"])
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
		if best_b < 0:
			break
		in_tree[best_b] = true
		edges.append([best_a, best_b])
	# a few extra links so the network has loops instead of a pure tree
	for k in 3:
		var a := rng.randi_range(0, cities.size() - 1)
		var b := rng.randi_range(0, cities.size() - 1)
		if a == b:
			continue
		var d: float = (cities[a]["c"] as Vector2).distance_to(cities[b]["c"])
		if d < 3400.0:
			edges.append([a, b])
	for e in edges:
		links.append(_build_link(int(e[0]), int(e[1]), rng))

func _build_link(ai: int, bi: int, rng: RandomNumberGenerator) -> Array:
	var a: Dictionary = cities[ai]
	var b: Dictionary = cities[bi]
	var ca: Vector2 = a["c"]
	var cb: Vector2 = b["c"]
	var dir := (cb - ca).normalized()
	var start: Vector2 = ca + dir * (float(a["r"]) + 6.0)
	var end: Vector2 = cb - dir * (float(b["r"]) + 6.0)
	var span := start.distance_to(end)
	if span < 30.0:
		return []
	var steps := maxi(6, int(span / 34.0))
	var perp := Vector2(-dir.y, dir.x)
	var amp := rng.randf_range(70.0, 230.0)
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var pts: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := start.lerp(end, t)
		var w := sin(t * PI) * amp * (sin(t * 3.1 + ph) * 0.7 + sin(t * 6.7 + ph2) * 0.3)
		# gentle S curve, plus a bit of noise so no two roads look alike
		w += sin(t * PI) * island._n_coast.get_noise_2d(p.x * 0.6, p.y * 0.6) * 90.0
		p += perp * w
		pts.append(p)
	# heights from the island, then smoothed so the road is drivable
	var hs: Array = []
	for p in pts:
		hs.append(maxf(island.raw_height(p.x, p.y), Island.SEA + 3.2))
	for pass_i in 3:
		var out: Array = []
		for i in hs.size():
			var acc := 0.0
			var cnt := 0
			for k in range(-2, 3):
				var j := clampi(i + k, 0, hs.size() - 1)
				acc += float(hs[j])
				cnt += 1
			out.append(acc / float(cnt))
		hs = out
	var out2: Array = []
	for i in pts.size():
		var p: Vector2 = pts[i]
		out2.append(Vector3(p.x, float(hs[i]), p.y))
	return out2

func _sample_roads() -> void:
	samples.clear()
	for link in links:
		var pts: Array = link
		if pts.size() < 2:
			continue
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 9.0))
			for k in n:
				samples.append(a.lerp(b, float(k) / float(n)))

## Points the island bakes into the terrain so the roads sit flush.
func flatten_points() -> Array:
	var out: Array = []
	for link in links:
		var pts: Array = link
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 22.0))
			for k in n:
				var p := a.lerp(b, float(k) / float(n))
				out.append({"p": Vector3(p.x, p.y, p.z), "r": 30.0})
	return out

## Bucket every road sample into a 16 m grid, so "is this spot on a road?" is a
## lookup over nine buckets instead of a scan over thousands of samples.
const ROAD_CELL := 16.0

func _index_roads() -> void:
	road_cells.clear()
	for s in samples:
		var v: Vector3 = s
		var k := Vector2i(int(floor(v.x / ROAD_CELL)), int(floor(v.z / ROAD_CELL)))
		if road_cells.has(k):
			(road_cells[k] as Array).append(v)
		else:
			road_cells[k] = [v]

## True when a point is within `pad` metres of any road.
func near_road(p: Vector3, pad: float = 8.0) -> bool:
	if road_cells.is_empty():
		_index_roads()
	var cx := int(floor(p.x / ROAD_CELL))
	var cz := int(floor(p.z / ROAD_CELL))
	var r := int(ceil(pad / ROAD_CELL))
	var lim := pad * pad
	for dz in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var bucket = road_cells.get(Vector2i(cx + dx, cz + dz))
			if bucket == null:
				continue
			for v in bucket:
				if (v as Vector3).distance_squared_to(p) < lim:
					return true
	return false

## Closest point on any road (used by respawn and by the parked cars).
func nearest_road_point(p: Vector3) -> Vector3:
	var best := p
	var bd := 1.0e18
	for s in samples:
		var d: float = (s as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			best = s
	return best

## The bit of road nearest to a point: returns [position, direction].
func nearest_road_segment(p: Vector3) -> Array:
	var bi := 0
	var bd := 1.0e18
	for i in samples.size():
		var d: float = (samples[i] as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			bi = i
	var a: Vector3 = samples[clampi(bi - 1, 0, samples.size() - 1)]
	var b: Vector3 = samples[clampi(bi + 1, 0, samples.size() - 1)]
	return [samples[bi], (b - a).normalized()]

# ------------------------------------------------------------------ parking

func _parking(rng: RandomNumberGenerator) -> void:
	street_cars.clear()
	for ci in cities.size():
		var c: Dictionary = cities[ci]
		var n := float(c["blocks"])
		var centre: Vector2 = c["c"]
		var y: float = float(c["h"])
		var half := n * CityConfig.CELL * 0.5
		# cars parked in the streets of every town: pick a road line (the gaps
		# between two blocks), then a spot along it, then a lane offset
		for k in 7:
			var along_x := rng.randf() < 0.5
			var line := float(rng.randi_range(0, int(n)))
			var off := (line - (n - 1.0) * 0.5) * CityConfig.CELL - CityConfig.CELL * 0.5
			var t := rng.randf_range(-0.62, 0.62) * half
			var pos: Vector2
			var yaw: float
			if along_x:
				pos = centre + Vector2(t, off + CityConfig.LANE)
				yaw = -PI * 0.5
			else:
				pos = centre + Vector2(off + CityConfig.LANE, t)
				yaw = 0.0
			street_cars.append({"pos": Vector3(pos.x, y + 0.35, pos.y), "yaw": yaw, "city": ci})
	# plenty more parked out on the open road between the towns
	if links.size() > 0 and samples.size() > 20:
		var stride := maxi(9, int(float(samples.size()) / 70.0))
		var idx := 4
		while idx < samples.size() - 4:
			var p: Vector3 = samples[idx]
			if rng.randf() < 0.62:
				_open_road_car(p, idx, rng)
			idx += stride + rng.randi_range(0, 2)

func _open_road_car(p: Vector3, idx: int, rng: RandomNumberGenerator) -> void:
	var q: Vector3 = samples[clampi(idx + 2, 0, samples.size() - 1)]
	var dir := (q - p)
	dir.y = 0.0
	if dir.length() < 0.1:
		return
	var yaw := atan2(-dir.x, -dir.z)
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * CityConfig.LANE
	var spot := Vector3(p.x, p.y + 0.35, p.z) + side
	# no car on top of the one behind it
	for other in street_cars:
		if Vector3(other["pos"]).distance_squared_to(spot) < 22.0 * 22.0:
			if int(other["city"]) == -1:
				return
	street_cars.append({"pos": spot, "yaw": yaw, "city": -1})
