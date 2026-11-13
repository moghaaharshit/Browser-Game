class_name Weapons
extends RefCounted

## Every gun in the game, Free-Fire style: one pistol, two SMGs, a shotgun,
## three assault rifles, an LMG and two bolt-action snipers.  All numbers are
## "game numbers" (damage / rpm / mag) tuned so a fight feels like a mobile
## battle-royale: fast TTK for rifles, one-shot headshots for the snipers.
##
## The dictionary keys are the contract used by CombatSystem, GunModel and the
## combat HUD.

enum { PISTOL, SMG, AR, SHOTGUN, LMG, SNIPER }

const LIST := [
	{
		"id": "M500", "name": "M500", "kind": PISTOL,
		"damage": 62.0, "rpm": 150.0, "mag": 6, "reserve": 48, "auto": false,
		"pellets": 1, "spread": 1.1, "ads_spread": 0.35, "recoil": 2.6, "kick": 0.9,
		"reload": 1.7, "scope": false, "sight": "reddot", "zoom": 44.0, "head": 2.6, "range": 90.0,
		"tracer": Color("ffd98a"), "furniture": Color("2a2c31"), "metal": Color("8e949b"),
	},
	{
		"id": "UMP", "name": "UMP", "kind": SMG,
		"damage": 22.0, "rpm": 700.0, "mag": 25, "reserve": 150, "auto": true,
		"pellets": 1, "spread": 1.5, "ads_spread": 0.65, "recoil": 1.5, "kick": 0.5,
		"reload": 2.1, "scope": false, "sight": "reddot", "zoom": 42.0, "head": 2.1, "range": 110.0,
		"tracer": Color("ffe08a"), "furniture": Color("33363c"), "metal": Color("7d848c"),
	},
	{
		"id": "MP40", "name": "MP40", "kind": SMG,
		"damage": 17.0, "rpm": 950.0, "mag": 30, "reserve": 180, "auto": true,
		"pellets": 1, "spread": 1.8, "ads_spread": 0.85, "recoil": 1.2, "kick": 0.4,
		"reload": 1.9, "scope": false, "sight": "reddot", "zoom": 42.0, "head": 2.0, "range": 100.0,
		"tracer": Color("ffd06a"), "furniture": Color("25272b"), "metal": Color("6f767d"),
	},
	{
		"id": "M1014", "name": "M1014", "kind": SHOTGUN,
		"damage": 13.0, "rpm": 110.0, "mag": 6, "reserve": 36, "auto": false,
		"pellets": 10, "spread": 7.5, "ads_spread": 6.0, "recoil": 6.0, "kick": 2.0,
		"reload": 2.6, "scope": false, "sight": "reddot", "zoom": 46.0, "head": 1.5, "range": 45.0,
		"tracer": Color("ffc46a"), "furniture": Color("1f2124"), "metal": Color("5d6469"),
	},
	{
		"id": "AK47", "name": "AK47", "kind": AR,
		"damage": 34.0, "rpm": 560.0, "mag": 30, "reserve": 180, "auto": true,
		"pellets": 1, "spread": 1.1, "ads_spread": 0.32, "recoil": 2.3, "kick": 0.8,
		"reload": 2.2, "scope": false, "sight": "reddot", "zoom": 36.0, "head": 2.2, "range": 190.0,
		"tracer": Color("ffe6a0"), "furniture": Color("6b4a2f"), "metal": Color("4d5257"),
	},
	{
		"id": "M4A1", "name": "M4A1", "kind": AR,
		"damage": 30.0, "rpm": 640.0, "mag": 30, "reserve": 180, "auto": true,
		"pellets": 1, "spread": 0.95, "ads_spread": 0.28, "recoil": 1.7, "kick": 0.6,
		"reload": 2.0, "scope": false, "sight": "reddot", "zoom": 36.0, "head": 2.2, "range": 200.0,
		"tracer": Color("fff2c0"), "furniture": Color("2b2e33"), "metal": Color("757c83"),
	},
	{
		"id": "SCAR", "name": "SCAR", "kind": AR,
		"damage": 36.0, "rpm": 540.0, "mag": 30, "reserve": 150, "auto": true,
		"pellets": 1, "spread": 1.05, "ads_spread": 0.30, "recoil": 2.1, "kick": 0.75,
		"reload": 2.3, "scope": false, "sight": "reddot", "zoom": 36.0, "head": 2.2, "range": 200.0,
		"tracer": Color("ffe6a0"), "furniture": Color("8a7a52"), "metal": Color("565b60"),
	},
	{
		"id": "M60", "name": "M60", "kind": LMG,
		"damage": 38.0, "rpm": 480.0, "mag": 100, "reserve": 200, "auto": true,
		"pellets": 1, "spread": 1.9, "ads_spread": 0.95, "recoil": 2.0, "kick": 0.9,
		"reload": 4.2, "scope": false, "sight": "reddot", "zoom": 38.0, "head": 1.9, "range": 190.0,
		"tracer": Color("ffdb8a"), "furniture": Color("3a3d42"), "metal": Color("6f767d"),
	},
	{
		"id": "KAR98K", "name": "KAR98K", "kind": SNIPER,
		"damage": 92.0, "rpm": 42.0, "mag": 5, "reserve": 25, "auto": false,
		"pellets": 1, "spread": 0.35, "ads_spread": 0.03, "recoil": 5.5, "kick": 2.4,
		"reload": 3.0, "scope": true, "sight": "sniper", "zoom": 20.0, "head": 2.4, "range": 420.0,
		"tracer": Color("ffffff"), "furniture": Color("5d4126"), "metal": Color("3f454a"),
	},
	{
		"id": "AWM", "name": "AWM", "kind": SNIPER,
		"damage": 118.0, "rpm": 38.0, "mag": 5, "reserve": 25, "auto": false,
		"pellets": 1, "spread": 0.25, "ads_spread": 0.02, "recoil": 6.5, "kick": 2.8,
		"reload": 3.4, "scope": true, "sight": "sniper", "zoom": 16.0, "head": 2.5, "range": 520.0,
		"tracer": Color("ffffff"), "furniture": Color("23262a"), "metal": Color("565d64"),
	},
]

const GRENADE_MAX := 4
const GLOO_MAX := 3

static func get_def(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]

static func count() -> int:
	return LIST.size()

## Degrees of cone for a shot: standing spread, tighter when aiming down sights,
## tighter still when crouched / prone.
static func cone(def: Dictionary, ads: bool, stance: int) -> float:
	var c: float = float(def["ads_spread"]) if ads else float(def["spread"])
	if stance == 1:
		c *= 0.72
	elif stance == 2:
		c *= 0.5
	return c
