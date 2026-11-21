extends CanvasLayer
## All on-screen UI: HP bar with face, inventory (E), spell ring (Q),
## spellbook, spell-upgrade choice. Built in code; reads from the Game
## autoload and redraws on Game.changed.

const SLOT := 24                          # 16 px icon + 4 px inset each side
const FONT := preload("res://assets/fonts/pixel.fnt")
const FONT_SIZE := 10                     # native size of the pixel font
const SHADOW := Color(0.02, 0.02, 0.08, 0.9)
const TEX_WINDOW := preload("res://assets/ui/window.png")
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
var tool_icon: TextureRect
var hand_icons := {}             # "left"/"right" -> TextureRect of the worn gauntlet
var energy_bar: Control
var energy_hint: Label
var slot_normal: StyleBox
var slot_equipped: StyleBox
var build_label: Label
var boss_box: Control
var boss_status: Label
var inv_panel: PanelContainer
var slots: Array[Button] = []
var slot_counts: Array[Label] = []
var coins_label: Label
var stats_label: Label
var stats_values: Label
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
var fade: ColorRect              # full-screen black for the cave intro
var title: Label
var subtitle: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # UI keeps working while paused
	_build_hud()
	_build_inventory()
	_build_book()
	_build_ring()
	_build_upgrade()
	_build_cinema()
	Game.changed.connect(refresh)
	Game.upgrade_ready.connect(_on_upgrade_ready)
	refresh()


# --- helpers ---------------------------------------------------------------

func _window(margin := 8) -> StyleBoxTexture:
	## SNES menu window: blue gradient, white bevelled frame (9-slice).
	var sb := StyleBoxTexture.new()
	sb.texture = TEX_WINDOW
	sb.set_texture_margin_all(4)
	sb.set_content_margin_all(margin)
	return sb


func _slot_box(name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/ui/%s.png" % name)
	sb.set_texture_margin_all(4)
	sb.set_content_margin_all(4)
	return sb


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
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", SHADOW)   # SNES-style drop shadow
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 1)
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
	face.position = Vector2(SCREEN.x / 2.0 - 8.0, SCREEN.y - 34.0)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # 32x32 texture shown at 16x16
	face.size = Vector2(16, 16)
	add_child(face)

	hp_bar = Control.new()
	hp_bar.position = Vector2(SCREEN.x / 2.0 - 40.0, SCREEN.y - 16.0)
	hp_bar.size = Vector2(80, 7)
	hp_bar.draw.connect(_draw_hp)
	add_child(hp_bar)

	energy_bar = Control.new()
	energy_bar.position = Vector2(SCREEN.x / 2.0 - 40.0, SCREEN.y - 8.0)
	energy_bar.size = Vector2(80, 5)
	energy_bar.draw.connect(_draw_energy)
	add_child(energy_bar)
	energy_hint = _label("R: COMBO", GOLD)
	energy_hint.position = Vector2(SCREEN.x / 2.0 + 64.0, SCREEN.y - 13.0)
	add_child(energy_hint)

	# worn gauntlets: left hand (Q) left of the bars, right hand (RMB) right
	for hand in ["left", "right"]:
		var x := SCREEN.x / 2.0 - 64.0 if hand == "left" else SCREEN.x / 2.0 + 46.0
		var ic := TextureRect.new()
		ic.position = Vector2(x, SCREEN.y - 22.0)
		add_child(ic)
		hand_icons[hand] = ic
		var key := _label("Q" if hand == "left" else "RMB", Color(0.85, 0.9, 1.0))
		key.size = Vector2(26, 11)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.position = Vector2(x - 5, SCREEN.y - 34.0)
		add_child(key)
		hand_icons[hand + "_key"] = key

	tool_icon = TextureRect.new()
	tool_icon.position = Vector2(SCREEN.x / 2.0 - 88.0, SCREEN.y - 22.0)
	add_child(tool_icon)

	boss_box = Control.new()
	boss_box.position = Vector2(SCREEN.x / 2.0 - 90.0, 4)
	boss_box.size = Vector2(180, 34)
	boss_box.draw.connect(_draw_boss_bar)
	add_child(boss_box)
	var boss_name := _label("HIVE MANTIS", Color(0.85, 0.6, 1.0))
	boss_name.size = Vector2(180, 12)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_name)
	boss_status = _label()
	boss_status.position = Vector2(0, 21)
	boss_status.size = Vector2(180, 12)
	boss_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_status)

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


func _draw_energy() -> void:
	var w := energy_bar.size.x
	var h := energy_bar.size.y
	var frac := Game.energy / Game.MAX_ENERGY
	energy_bar.draw_rect(Rect2(0, 0, w, h), Color("10121e"))
	energy_bar.draw_rect(Rect2(1, 1, w - 2, h - 2), Color("1a2240"))
	var full := frac >= 1.0
	var col := Color("3aa0f0")
	if full:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
		col = Color("f2c94a").lerp(Color("fff6c0"), pulse)
	energy_bar.draw_rect(Rect2(1, 1, (w - 2) * frac, h - 2), col)
	energy_bar.draw_rect(Rect2(1, 1, (w - 2) * frac, 1), col.lightened(0.4))


func _process(_delta: float) -> void:
	# cooldown dimming of the worn gauntlets, pulsing combo bar
	var player = get_parent().player if get_parent() else null
	for hand in ["left", "right"]:
		var ic: TextureRect = hand_icons[hand]
		var cd: float = player.cooldowns.get(Game.hands[hand], 0.0) if player else 0.0
		ic.modulate = Color(0.45, 0.45, 0.55) if cd > 0.0 else Color.WHITE
	var full := Game.energy >= Game.MAX_ENERGY and not Game.cutscene
	energy_hint.visible = full and int(Time.get_ticks_msec() / 400) % 2 == 0
	if full:
		energy_bar.queue_redraw()


func _draw_boss_bar() -> void:
	if Game.boss.is_empty():
		return
	var r := Rect2(0, 13, boss_box.size.x, 7)
	var frac: float = Game.boss["heart"] / Game.boss["max"]
	boss_box.draw_rect(r, Color("1a1220"))
	boss_box.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 5)), Color("3a1030"))
	boss_box.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2) * frac, 5)), Color("c0203a"))
	boss_box.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((r.size.x - 2) * frac, 2)), Color("f06a80"))


# --- inventory -------------------------------------------------------------

func _build_inventory() -> void:
	inv_panel = PanelContainer.new()
	inv_panel.add_theme_stylebox_override("panel", _window(10))
	inv_panel.visible = false
	_centered(inv_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	inv_panel.add_child(row)

	var left := VBoxContainer.new()
	row.add_child(left)
	left.add_theme_constant_override("separation", 4)
	left.add_child(_label("GAUNTLET ALCHEMIST", GOLD))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	left.add_child(grid)

	var normal := _slot_box("slot")
	var hover := _slot_box("slot_hover")
	slot_normal = normal
	slot_equipped = _slot_box("slot_equipped")
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
		b.gui_input.connect(_on_slot_input.bind(i))
		grid.add_child(b)
		slots.append(b)
		var cnt := _label()
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cnt.position = Vector2(0, SLOT - 12)
		cnt.size = Vector2(SLOT - 2, 11)
		b.add_child(cnt)
		slot_counts.append(cnt)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(96, 0)
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	right.add_child(_label("STATUS", GOLD))
	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 6)
	stats_label = _label()
	stats_values = _label("", Color("f8f0c0"))
	stats_values.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_row.add_child(stats_label)
	stat_row.add_child(stats_values)
	right.add_child(stat_row)
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 4)
	var coin := TextureRect.new()
	coin.texture = Game.icons["money"]
	coin_row.add_child(coin)
	coins_label = _label("", GOLD)
	coins_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_row.add_child(coins_label)
	right.add_child(coin_row)
	right.add_child(_label("Gauntlet: click=RMB\n  right-click=Q\nTool: click to hold\nBook: powers, combos", Color(0.8, 0.85, 1.0, 0.75)))


func _build_book() -> void:
	book_panel = PanelContainer.new()
	book_panel.add_theme_stylebox_override("panel", _window(12))
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
	upgrade_panel.add_theme_stylebox_override("panel", _window(12))
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

	var normal := _slot_box("slot")
	var hover := _slot_box("slot_hover")
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


# --- cinematic -------------------------------------------------------------

func _build_cinema() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10                  # above the HUD
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.size = SCREEN
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	title = _label("", Color(0.9, 0.65, 1.0))
	title.add_theme_font_size_override("font_size", FONT_SIZE * 2)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	subtitle = _label("", Color(1, 1, 1, 0.85))
	for l in [title, subtitle]:
		l.size = Vector2(SCREEN.x, 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.modulate.a = 0.0
		layer.add_child(l)
	title.position = Vector2(0, SCREEN.y - 78)
	subtitle.position = Vector2(0, SCREEN.y - 50)


func show_title(big: String, small: String, hold: float) -> void:
	title.text = big
	subtitle.text = small
	var tw := create_tween().set_parallel()
	for l in [title, subtitle]:
		l.modulate.a = 0.0
		tw.tween_property(l, "modulate:a", 1.0, 0.25)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(title, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(subtitle, "modulate:a", 0.0, 0.4)


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
		KEY_ESCAPE:
			_set_inventory(false)
			_set_ring(false)
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
	if slot == null:
		return
	if slot["id"] == "spellbook":
		book_panel.visible = not book_panel.visible
	elif Game.TOOLS.has(slot["id"]):
		Game.equip(slot["id"])
	elif Game.GAUNTLET_OF.has(slot["id"]):
		Game.equip_gauntlet(slot["id"], "right")


func _on_slot_input(event: InputEvent, i: int) -> void:
	## Right-click a gauntlet: wear it on the left hand (Q).
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		var slot = Game.inventory[i]
		if slot != null and Game.GAUNTLET_OF.has(slot["id"]):
			Game.equip_gauntlet(slot["id"], "left")


# --- refresh ---------------------------------------------------------------

func refresh() -> void:
	face.texture = Game.icons["face_hurt"] if Game.hp <= 3 else Game.icons["face"]
	hp_bar.queue_redraw()
	build_label.visible = Game.build_mode
	for n in [face, hp_bar, tool_icon]:
		n.visible = not Game.cutscene
	boss_box.visible = Game.boss.get("visible", false) and not Game.cutscene
	if boss_box.visible:
		if Game.boss["open"]:
			boss_status.text = "Cage open! Burn the heart with fire!"
			boss_status.add_theme_color_override("font_color", Color(1, 0.7, 0.4))
		else:
			boss_status.text = "Claw cage: %d/%d fist hits to burst it" % [Game.boss["cage_hits"], Game.boss["cage_needed"]]
			boss_status.add_theme_color_override("font_color", Color.WHITE)
		boss_box.queue_redraw()
	tool_icon.texture = Game.icons[Game.equipped]
	for hand in ["left", "right"]:
		hand_icons[hand].texture = Game.icons["g_" + Game.hands[hand]]
		hand_icons[hand].visible = not Game.cutscene
		hand_icons[hand + "_key"].visible = not Game.cutscene
	energy_bar.visible = not Game.cutscene
	energy_bar.queue_redraw()

	for i in Game.SLOTS:
		var slot = Game.inventory[i]
		slots[i].icon = Game.icons[slot["id"]] if slot != null else null
		slot_counts[i].text = str(slot["count"]) if slot != null and slot["count"] > 1 else ""
		var hand := Game.hand_of(slot["id"]) if slot != null else ""
		if hand != "":
			slot_counts[i].text = "Q" if hand == "left" else "R"
		var is_equipped: bool = slot != null and (slot["id"] == Game.equipped or hand != "")
		slots[i].add_theme_stylebox_override("normal", slot_equipped if is_equipped else slot_normal)

	coins_label.text = "%d G" % Game.money
	var names := PackedStringArray()
	var values := PackedStringArray()
	for s in Game.STAT_ORDER:
		names.append(s.capitalize())
		values.append(str(Game.stat_level(s)))
	stats_label.text = "\n".join(names)
	stats_values.text = "\n".join(values)

	var book := PackedStringArray(["GAUNTLET POWERS", ""])
	for id in Game.SPELL_ORDER:
		var sp: Dictionary = Game.SPELLS[id]
		var worn := ""
		for h in Game.hands:
			if Game.hands[h] == id:
				worn = "  [%s]" % ("Q" if h == "left" else "RMB")
		book.append("%s  Lv %d  Dmg %.1f  Cost: %s%s" % [sp["name"], Game.spell_level(id),
			Game.spell_damage(id), Game.cost_text(id), worn])
		var up_txt := "Upgrade: " + Game.upgrade_name(id) if Game.spell_upgrade[id] != "" \
			else "Upgrade at %d hits: %d/%d" % [Game.UPGRADE_HITS, mini(Game.spell_hits[id], Game.UPGRADE_HITS), Game.UPGRADE_HITS]
		book.append("   %s.  %s" % [sp["info"], up_txt])
	book.append("")
	book.append("GAUNTLET COMBOS  (energy full: R)")
	for k in Game.COMBOS:
		var mark := "> " if k == Game.combo_key() else "  "
		var parts: PackedStringArray = k.split("+")
		book.append("%s%s: %s + %s" % [mark, Game.COMBOS[k]["name"], Game.SPELLS[parts[0]]["name"], Game.SPELLS[parts[1]]["name"]])
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
