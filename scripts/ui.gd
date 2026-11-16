extends CanvasLayer
## All on-screen UI: HP bar with face, inventory (E), spell ring (Q),
## spellbook, spell-upgrade choice. Built in code; reads from the Game
## autoload and redraws on Game.changed.

const SLOT := 18
const PANEL_BG := Color("1d2b6b")        # SNES-style blue menu
const PANEL_BORDER := Color("e8e8ff")
const SLOT_BG := Color("101a48")
const SLOT_HOVER := Color("2d3f8f")
const GOLD := Color("f2d64b")
const RING_CENTER := Vector2(240, 135)
const RING_RADIUS := 46.0
const SCREEN := Vector2(480, 270)

var face: TextureRect
var hp_bar: Control
var build_label: Label
var inv_panel: PanelContainer
var slots: Array[Button] = []
var slot_counts: Array[Label] = []
var coins_label: Label
var stats_label: Label
var book_panel: PanelContainer
var book_label: Label
var ring: Control
var ring_items := {}     # spell id -> {"button": TextureButton, "label": Label, "pos": Vector2}
var upgrade_panel: PanelContainer
var upgrade_title: Label
var upgrade_labels: Array[Label] = []
var upgrade_icons: Array[TextureRect] = []
var upgrade_icon: TextureRect
var pending_upgrades: Array[String] = []
var upgrade_spell := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # UI keeps working while paused
	_build_hud()
	_build_inventory()
	_build_book()
	_build_ring()
	_build_upgrade()
	Game.changed.connect(refresh)
	Game.upgrade_ready.connect(_on_upgrade_ready)
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
	cc.size = SCREEN
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	cc.add_child(c)


# --- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	face = TextureRect.new()
	face.position = Vector2(SCREEN.x / 2.0 - 8.0, SCREEN.y - 28.0)
	add_child(face)

	hp_bar = Control.new()
	hp_bar.position = Vector2(SCREEN.x / 2.0 - 40.0, SCREEN.y - 10.0)
	hp_bar.size = Vector2(80, 7)
	hp_bar.draw.connect(_draw_hp)
	add_child(hp_bar)

	build_label = _label("BUILD MODE  (B to exit)", GOLD)
	build_label.position = Vector2(4, 2)
	add_child(build_label)


func _draw_hp() -> void:
	var w := hp_bar.size.x
	var h := hp_bar.size.y
	var frac := float(Game.hp) / Game.MAX_HP
	hp_bar.draw_rect(Rect2(0, 0, w, h), Color("1a1220"))
	hp_bar.draw_rect(Rect2(1, 1, w - 2, h - 2), Color("4a1a20"))
	hp_bar.draw_rect(Rect2(1, 1, (w - 2) * frac, h - 2), Color("d8382c"))
	hp_bar.draw_rect(Rect2(1, 1, (w - 2) * frac, 2), Color("f2806a"))
	for i in range(1, Game.MAX_HP):
		var x := 1.0 + (w - 2.0) * i / Game.MAX_HP
		hp_bar.draw_line(Vector2(x, 1), Vector2(x, h - 1), Color(0, 0, 0, 0.35))


# --- inventory -------------------------------------------------------------

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


# --- spell ring ------------------------------------------------------------

func _build_ring() -> void:
	ring = Control.new()
	ring.size = SCREEN
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


# --- upgrade choice --------------------------------------------------------

func _build_upgrade() -> void:
	upgrade_panel = PanelContainer.new()
	upgrade_panel.add_theme_stylebox_override("panel", _box(Color("3a1d5e"), GOLD, 8))
	upgrade_panel.visible = false
	_centered(upgrade_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	upgrade_panel.add_child(v)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	upgrade_icon = TextureRect.new()
	head.add_child(upgrade_icon)
	upgrade_title = _label("", GOLD)
	head.add_child(upgrade_title)
	v.add_child(head)

	var normal := _box(PANEL_BG, Color("5a6ab0"), 2)
	var hover := _box(SLOT_HOVER, GOLD, 2)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 28)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.pressed.connect(_on_upgrade_chosen.bind(i))
		v.add_child(b)
		var ic := TextureRect.new()
		ic.position = Vector2(3, 2)
		ic.size = Vector2(24, 24)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		upgrade_icons.append(ic)
		var l := _label()
		l.position = Vector2(32, 3)
		l.size = Vector2(200, 22)
		b.add_child(l)
		upgrade_labels.append(l)


func _on_upgrade_ready(spell: String) -> void:
	pending_upgrades.append(spell)
	if not upgrade_panel.visible:
		_show_next_upgrade()


func _show_next_upgrade() -> void:
	if pending_upgrades.is_empty():
		upgrade_panel.visible = false
		get_tree().paused = false
		_update_ui_open()
		return
	upgrade_spell = pending_upgrades.pop_front()
	upgrade_icon.texture = Game.icons[upgrade_spell]
	upgrade_title.text = "  %s mastered! Choose an upgrade:" % Game.SPELLS[upgrade_spell]["name"]
	var options: Array = Game.UPGRADES[upgrade_spell]
	for i in 3:
		upgrade_labels[i].text = "%s\n%s" % [options[i]["name"], options[i]["desc"]]
		upgrade_icons[i].texture = Game.icons["up_" + options[i]["key"]]
	inv_panel.visible = false
	book_panel.visible = false
	ring.visible = false
	upgrade_panel.visible = true
	get_tree().paused = true
	_update_ui_open()


func _on_upgrade_chosen(i: int) -> void:
	Game.choose_upgrade(upgrade_spell, Game.UPGRADES[upgrade_spell][i]["key"])
	_show_next_upgrade()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if upgrade_panel.visible:
		return
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
	Game.ui_open = inv_panel.visible or ring.visible or upgrade_panel.visible


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
	face.texture = Game.icons["face_hurt"] if Game.hp <= 3 else Game.icons["face"]
	hp_bar.queue_redraw()
	build_label.visible = Game.build_mode

	for i in Game.SLOTS:
		var slot = Game.inventory[i]
		slots[i].icon = Game.icons[slot["id"]] if slot != null else null
		slot_counts[i].text = str(slot["count"]) if slot != null and slot["count"] > 1 else ""

	coins_label.text = " %d" % Game.money
	var lines := PackedStringArray()
	for s in Game.STAT_ORDER:
		lines.append("%s   %d" % [s.capitalize(), Game.stat_level(s)])
	stats_label.text = "\n".join(lines)

	var book := PackedStringArray(["SPELLBOOK"])
	for id in Game.SPELL_ORDER:
		var s: Dictionary = Game.SPELLS[id]
		book.append("")
		book.append("%s   Lv %d   (cast %d times)" % [s["name"], Game.spell_level(id), Game.spell_casts[id]])
		book.append("   Damage %.2f    Cost: %s" % [Game.spell_damage(id), Game.cost_text(id)])
		book.append("   " + s["info"])
		if Game.spell_upgrade[id] == "":
			book.append("   Upgrade unlocks at %d enemy hits: %d/%d" % [Game.UPGRADE_HITS,
				mini(Game.spell_hits[id], Game.UPGRADE_HITS), Game.UPGRADE_HITS])
		else:
			book.append("   Upgrade: " + Game.upgrade_name(id))
	book.append("")
	book.append("(click to close)")
	book_label.text = "\n".join(book)

	for id in ring_items:
		var it: Dictionary = ring_items[id]
		var title: String = Game.upgrade_name(id) if Game.spell_upgrade[id] != "" else Game.SPELLS[id]["name"]
		it["label"].text = "%s\n%s" % [title, Game.cost_text(id)]
		it["button"].texture_normal = Game.spell_icon(id)
		it["button"].modulate = Color.WHITE if Game.can_cast(id) else Color(1, 1, 1, 0.4)
	ring.queue_redraw()
