class_name CityConfig
extends RefCounted

## All the numbers that describe the city layout, plus the colour palette.
## The city is a grid of square blocks.  Roads run along every grid line.

const GRID := 78          # blocks per side
const BLOCK := 64.0       # block size (kerb to kerb)
const ROAD := 16.0        # road width
const CELL := 80.0        # BLOCK + ROAD, distance between two grid lines
const HALF_ROAD := 8.0    # ROAD * 0.5
const SIDEWALK := 4.0     # sidewalk width inside a block
const MAP := GRID * CELL  # ~6240 m across
const ORIGIN := -MAP * 0.5
const LANE := 4.0         # lane centre offset from the road centre line
const CURB := 0.12         # kerb lip height (visual only, drivable)
const CENTER := GRID / 2

# ---- grid helpers -------------------------------------------------------

static func road_coord(line: int) -> float:
	return ORIGIN + float(line) * CELL

static func line_at(x: float) -> int:
	return int(floor((x - ORIGIN) / CELL))

static func block_center(bx: int, bz: int) -> Vector3:
	return Vector3(
		ORIGIN + float(bx) * CELL + HALF_ROAD + BLOCK * 0.5,
		0.0,
		ORIGIN + float(bz) * CELL + HALF_ROAD + BLOCK * 0.5)

static func intersection_center(lx: int, lz: int) -> Vector3:
	return Vector3(road_coord(lx), 0.0, road_coord(lz))

static func right_of(dir: Vector3) -> Vector3:
	return dir.cross(Vector3.UP).normalized()

# ---- palette ------------------------------------------------------------

const C_ASPHALT := Color("2b2f36")
const C_ASPHALT_D := Color("23262c")
const C_LINE := Color("e8e6de")
const C_LINE_Y := Color("e8c33a")
const C_SIDEWALK := Color("a9aba4")
const C_SIDEWALK_D := Color("8d8f89")
const C_CONCRETE := Color("c8c4b8")
const C_CONCRETE_D := Color("9c9a90")
const C_GRASS := Color("4e7a3a")
const C_GRASS_D := Color("3d6330")
const C_TRUNK := Color("4a3524")
const C_LEAF1 := Color("2f6b34")
const C_LEAF2 := Color("3d8340")
const C_LEAF3 := Color("57944a")
const C_LEAF4 := Color("6aa353")

const C_GLOW_WIN := Color("ffd98a")
const C_GLOW_GLASS := Color("8fd9e8")
const C_GLOW_NEON_P := Color("ff3ba7")
const C_GLOW_NEON_C := Color("2ff2ff")
const C_GLOW_NEON_V := Color("b455ff")
const C_GLOW_NEON_Y := Color("ffd23b")
const C_GLOW_RED := Color("ff2b2b")
const C_GLOW_GREEN := Color("22ff66")

const C_ROOF_A := Color("7a3b2e")
const C_ROOF_B := Color("8f4a38")
const C_ROOF_C := Color("3f4a5a")
const C_ROOF_D := Color("5c3a52")
const C_WALL_A := Color("e6dcc8")
const C_WALL_B := Color("d9c3a5")
const C_WALL_C := Color("c9d6e2")
const C_WALL_D := Color("e8e4dd")
const C_WALL_E := Color("b9c6b4")
const C_BRICK := Color("a8543f")
const C_POLICE := Color("2f5fa8")
const C_HOSPITAL := Color("f2f4f5")
const C_METAL := Color("6d7378")
const C_METAL_D := Color("4b5054")
const C_DARK := Color("22242a")
const C_GLASS_D := Color("37505c")
const C_WOOD := Color("6b4a2f")
const C_ROCK := Color("5a5f66")
const C_SNOW := Color("eef4f8")

# --- district palette ---
const C_STONE := Color("cbc0a8")
const C_STONE_D := Color("a89c86")
const C_STONE_L := Color("ded6c2")
const C_RUST := Color("8a4a30")
const C_IND_YEL := Color("cbb83c")
const C_IND_WALL := Color("8d918d")
const C_IND_WALL_D := Color("6f7570")
const C_SHED_BLUE := Color("4a6f8a")
const C_CONTAINER := [Color("b8472f"), Color("2f6f8f"), Color("3f7a4a"), Color("c08a2f"), Color("7a4a8f")]
const C_DEAD_GRASS := Color("4a5a38")
const C_GRAVE := Color("8a8f8c")
const C_FIELD := Color("3f8a44")
const C_SAND := Color("d8c89a")
const C_DIRT := Color("8a7458")
const C_WATER := Color("2f7fa8")
const C_DESERT := Color("8a5a42")
