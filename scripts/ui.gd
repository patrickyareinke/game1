extends CanvasLayer
## All on-screen UI: HUD, inventory (E), spell ring (Q), spellbook.
## Built in code; it only reads from the Game autoload and redraws on Game.changed.

const SLOT := 18
const PANEL_BG := Color("1d2b6b")        # SNES-style blue menu
const PANEL_BORDER := Color("e8e8ff")
const SLOT_BG := Color("101a48")
const SLOT_HOVER := Color("2d3f8f")
const GOLD := Color("f2d64b")
const RING_CENTER := Vector2(240, 135)
const RING_RADIUS := 46.0

var hud_left: Label
var hud_hint: Label
var spell_icon: TextureRect
var spell_label: Label
var inv_panel: PanelContainer
var slots: Array[Button] = []
var slot_counts: Array[Label] = []
var coins_label: Label
var stats_label: Label
var book_panel: PanelContainer
var book_label: Label
var ring: Control
var ring_items := {}     # spell id -> {"button": TextureButton, "label": Label, "pos": Vector2}


func _ready() -> void:
	_build_hud()
	_build_inventory()
	_build_book()
	_build_ring()
	Game.changed.connect(refresh)
	refresh()


# --- helpers ---------------------------------------------------------------

func _box(bg: Color, border := PANEL_BORDER, margin := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.set_content_margin_all(margin)
	return sb


func _label(text := "", color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 2)
	return l


func _centered(c: Control) -> void:
	## Add c to a screen-sized CenterContainer so it stays centered.
	var cc := CenterContainer.new()
	cc.position = Vector2.ZERO
	cc.size = Vector2(480, 270)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	cc.add_child(c)


# --- building --------------------------------------------------------------

func _build_hud() -> void:
	hud_left = _label()
	hud_left.position = Vector2(4, 2)
	add_child(hud_left)

	hud_hint = _label("", Color(1, 1, 1, 0.8))
	hud_hint.position = Vector2(4, 256)
	add_child(hud_hint)

	spell_icon = TextureRect.new()
	spell_icon.position = Vector2(460, 3)
	add_child(spell_icon)
	spell_label = _label()
	spell_label.position = Vector2(256, 5)
	spell_label.size = Vector2(200, 12)
	spell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(spell_label)


func _build_inventory() -> void:
	inv_panel = PanelContainer.new()
	inv_panel.add_theme_stylebox_override("panel", _box(PANEL_BG, PANEL_BORDER, 6))
	inv_panel.visible = false
	_centered(inv_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	inv_panel.add_child(row)

	var left := VBoxContainer.new()
	row.add_child(left)
	left.add_child(_label("INVENTORY", GOLD))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	left.add_child(grid)

	var normal := _box(SLOT_BG, Color("5a6ab0"), 1)
	var hover := _box(SLOT_HOVER, GOLD, 1)
	for i in Game.SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(SLOT, SLOT)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("pressed", hover)
		b.add_theme_stylebox_override("hover", hover)
		b.pressed.connect(_on_slot_pressed.bind(i))
		grid.add_child(b)
		slots.append(b)
		var cnt := _label()
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.position = Vector2(0, 7)
		cnt.size = Vector2(SLOT - 1, 10)
		b.add_child(cnt)
		slot_counts.append(cnt)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(80, 0)
	row.add_child(right)
	var coin_row := HBoxContainer.new()
	var coin := TextureRect.new()
	coin.texture = Game.icons["coin"]
	coin_row.add_child(coin)
	coins_label = _label("", GOLD)
	coin_row.add_child(coins_label)
	right.add_child(coin_row)
	right.add_child(_label("STATS", GOLD))
	stats_label = _label()
	right.add_child(stats_label)
	right.add_child(_label("\nClick the book\nto read spells", Color(1, 1, 1, 0.6)))


func _build_book() -> void:
	book_panel = PanelContainer.new()
	book_panel.add_theme_stylebox_override("panel", _box(Color("3a1d5e"), GOLD, 8))
	book_panel.visible = false
	book_panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			book_panel.visible = false)
	_centered(book_panel)
	book_label = _label()
	book_panel.add_child(book_label)


func _build_ring() -> void:
	ring = Control.new()
	ring.size = Vector2(480, 270)
	ring.visible = false
	ring.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_set_ring(false))            # click outside the icons closes the ring
	ring.draw.connect(_draw_ring)
	add_child(ring)

	var n := Game.SPELL_ORDER.size()
	for i in n:
		var id: String = Game.SPELL_ORDER[i]
		var pos := RING_CENTER + Vector2.from_angle(-PI / 2.0 + TAU * i / n) * RING_RADIUS
		var b := TextureButton.new()
		b.texture_normal = Game.icons[id]
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.size = Vector2(32, 32)
		b.position = pos - Vector2(16, 16)
		b.pressed.connect(_pick_spell.bind(id))
		ring.add_child(b)
		var l := _label()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(120, 20)
		l.position = pos + Vector2(-60, 17)
		ring.add_child(l)
		ring_items[id] = {"button": b, "label": l, "pos": pos}


func _draw_ring() -> void:
	ring.draw_circle(RING_CENTER, 80.0, Color(0, 0, 0.1, 0.55))
	ring.draw_arc(RING_CENTER, RING_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 1.0)
	var pos: Vector2 = ring_items[Game.active_spell]["pos"]
	ring.draw_circle(pos, 20.0, Color(GOLD, 0.45))


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not (key and key.pressed and not key.echo):
		return
	match key.physical_keycode:
		KEY_E:
			_set_inventory(not inv_panel.visible)
		KEY_Q:
			_set_ring(not ring.visible)
		KEY_ESCAPE:
			_set_inventory(false)
			_set_ring(false)
		KEY_1, KEY_2, KEY_3:
			_pick_spell(Game.SPELL_ORDER[key.physical_keycode - KEY_1])
		_:
			return
	get_viewport().set_input_as_handled()


func _set_inventory(open: bool) -> void:
	inv_panel.visible = open
	if not open:
		book_panel.visible = false
	if open:
		ring.visible = false
	_update_ui_open()


func _set_ring(open: bool) -> void:
	ring.visible = open
	if open:
		inv_panel.visible = false
		book_panel.visible = false
		refresh()
	_update_ui_open()


func _update_ui_open() -> void:
	Game.ui_open = inv_panel.visible or ring.visible


func _pick_spell(id: String) -> void:
	Game.active_spell = id
	_set_ring(false)
	refresh()


func _on_slot_pressed(i: int) -> void:
	var slot = Game.inventory[i]
	if slot != null and slot["id"] == "spellbook":
		book_panel.visible = not book_panel.visible


# --- refresh ---------------------------------------------------------------

func refresh() -> void:
	for i in Game.SLOTS:
		var slot = Game.inventory[i]
		slots[i].icon = Game.icons[slot["id"]] if slot != null else null
		slot_counts[i].text = str(slot["count"]) if slot != null and slot["count"] > 1 else ""

	coins_label.text = " %d" % Game.money
	var lines := PackedStringArray()
	for s in Game.STAT_ORDER:
		lines.append("%-9s %d" % [s.capitalize(), Game.stat_level(s)])
	stats_label.text = "\n".join(lines)

	hud_left.text = "HP %d/%d    Coins %d" % [Game.hp, Game.MAX_HP, Game.money]
	if Game.build_mode:
		hud_hint.text = "BUILD MODE   LMB place   RMB remove   B exit"
	else:
		hud_hint.text = "WASD move  LMB stick  RMB spell  Q spells  E inventory  F water  B build"

	var sp: Dictionary = Game.SPELLS[Game.active_spell]
	spell_icon.texture = Game.icons[Game.active_spell]
	spell_label.text = "%s  [%s]" % [sp["name"], Game.cost_text(Game.active_spell)]
	spell_label.add_theme_color_override("font_color",
		Color.WHITE if Game.can_cast(Game.active_spell) else Color(1, 0.5, 0.5))

	var book := PackedStringArray(["SPELLBOOK", ""])
	for id in Game.SPELL_ORDER:
		var s: Dictionary = Game.SPELLS[id]
		book.append("%s   Lv %d   (cast %d times)" % [s["name"], Game.spell_level(id), Game.spell_casts[id]])
		book.append("   Damage %.2f    Cost: %s" % [Game.spell_damage(id), Game.cost_text(id)])
		book.append("   " + s["info"])
		book.append("")
	book.append("(click to close)")
	book_label.text = "\n".join(book)

	for id in ring_items:
		var it: Dictionary = ring_items[id]
		it["label"].text = "%s\n%s" % [Game.SPELLS[id]["name"], Game.cost_text(id)]
		it["button"].modulate = Color.WHITE if Game.can_cast(id) else Color(1, 1, 1, 0.4)
	ring.queue_redraw()
