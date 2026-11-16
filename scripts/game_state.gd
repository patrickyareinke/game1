extends Node
## Global game state (autoload "Game"): inventory, money, stats, spells, HP.
## Everything that changes emits `changed`, and the UI redraws from it.

signal changed

const SLOTS := 40                    # 8 columns x 5 rows
const MAX_HP := 10

const ITEMS := {
	"stick": {"name": "Stick"},
	"spellbook": {"name": "Spellbook"},
	"oil": {"name": "Oil"},
	"ash": {"name": "Ash"},
	"water": {"name": "Water"},
}

const SPELLS := {
	"fireball": {"name": "Fireball", "cost": {"oil": 1, "ash": 1}, "damage": 3.0,
		"cooldown": 0.6, "info": "Flies straight, burns bushes into ash"},
	"mudball": {"name": "Mudball", "cost": {"water": 1}, "damage": 1.0,
		"cooldown": 0.45, "info": "Slows enemies for 3 s"},
	"fiststamp": {"name": "Magic Fiststamp", "cost": {}, "damage": 2.0,
		"cooldown": 2.0, "info": "Area hit at the cursor, knocks back"},
}
const SPELL_ORDER := ["fireball", "mudball", "fiststamp"]
const STAT_ORDER := ["fighter", "alchemy", "building", "fitness", "wisdom"]

# Stat / spell growth per action
const FITNESS_PER_TILE := 0.001
const FIGHTER_PER_HIT := 0.005
const ALCHEMY_PER_CAST := 0.005
const BUILDING_PER_BLOCK := 0.005
const SPELL_POWER_PER_CAST := 0.01

var icons := {}              # id -> Texture2D (items and spells)
var stats := {}              # name -> float, shown as whole numbers
var spell_power := {}        # spell id -> float
var spell_casts := {}        # spell id -> int
var inventory: Array = []    # SLOTS entries: null or {"id": String, "count": int}
var money := 0
var hp := MAX_HP
var active_spell := "fireball"
var ui_open := false         # inventory or spell ring visible -> no world clicks
var build_mode := false


func _ready() -> void:
	for id in ["stick", "spellbook", "oil", "ash", "water", "coin",
			"fireball", "mudball", "fiststamp"]:
		icons[id] = load("res://assets/icons/%s.png" % id)
	reset()


func reset() -> void:
	stats.clear()
	for s in STAT_ORDER:
		stats[s] = 1.0
	for s in SPELL_ORDER:
		spell_power[s] = 1.0
		spell_casts[s] = 0
	inventory.clear()
	inventory.resize(SLOTS)
	money = 0
	hp = MAX_HP
	add_item("stick")
	add_item("spellbook")
	add_item("oil", 3)
	add_item("ash", 3)
	add_item("water", 3)


# --- stats -----------------------------------------------------------------

func add_stat(stat: String, amount: float) -> void:
	stats[stat] += amount
	changed.emit()


func stat_level(stat: String) -> int:
	return floori(stats[stat] + 0.000001)   # epsilon against float rounding


# --- inventory -------------------------------------------------------------

func add_item(id: String, count: int = 1) -> void:
	for slot in inventory:
		if slot != null and slot["id"] == id:
			slot["count"] += count
			changed.emit()
			return
	for i in SLOTS:
		if inventory[i] == null:
			inventory[i] = {"id": id, "count": count}
			changed.emit()
			return
	# inventory full: item is lost (could drop it on the ground later)


func count_item(id: String) -> int:
	for slot in inventory:
		if slot != null and slot["id"] == id:
			return slot["count"]
	return 0


func remove_item(id: String, count: int = 1) -> void:
	for i in SLOTS:
		var slot = inventory[i]
		if slot != null and slot["id"] == id:
			slot["count"] -= count
			if slot["count"] <= 0:
				inventory[i] = null
			changed.emit()
			return


func add_money(amount: int) -> void:
	money += amount
	changed.emit()


func set_hp(value: int) -> void:
	hp = clampi(value, 0, MAX_HP)
	changed.emit()


# --- spells ----------------------------------------------------------------

func can_cast(spell: String) -> bool:
	var cost: Dictionary = SPELLS[spell]["cost"]
	for id in cost:
		if count_item(id) < cost[id]:
			return false
	return true


func missing_text(spell: String) -> String:
	var parts := PackedStringArray()
	var cost: Dictionary = SPELLS[spell]["cost"]
	for id in cost:
		parts.append(ITEMS[id]["name"])
	return "Need " + " + ".join(parts)


func cost_text(spell: String) -> String:
	var cost: Dictionary = SPELLS[spell]["cost"]
	if cost.is_empty():
		return "free"
	var parts := PackedStringArray()
	for id in cost:
		parts.append("%d %s (%d)" % [cost[id], ITEMS[id]["name"], count_item(id)])
	return " + ".join(parts)


func cast(spell: String) -> void:
	## Pay the ingredients and apply the learning effects.
	var cost: Dictionary = SPELLS[spell]["cost"]
	for id in cost:
		remove_item(id, cost[id])
	spell_power[spell] += SPELL_POWER_PER_CAST
	spell_casts[spell] += 1
	add_stat("alchemy", ALCHEMY_PER_CAST)


func spell_level(spell: String) -> int:
	return floori(spell_power[spell] + 0.000001)


func spell_damage(spell: String) -> float:
	return SPELLS[spell]["damage"] * spell_power[spell] * stats["alchemy"]


func stick_damage() -> float:
	return 1.0 * stats["fighter"]
