class_name ComputerScreen
extends CanvasLayer
## The in-world computer's desktop, "HomeLab OS" (docs/TERMINAL_DESIGN.md §2): Shop, Orders and
## Terminal apps. Shown full screen once the camera reaches the monitor (docs/INTERACTION_SYSTEM.md §6:
## the prototype uses the full-screen variant; the shared SubViewport is spike S2).

signal closed

var world: SimWorld
var pc_id: int = -1
var _root: PanelContainer
var _content: VBoxContainer
var _clock: Label
var _credits: Label
var _cart: Array[StringName] = []
var _page: StringName = &""
var _message: Label
var _terminal: TerminalView = null


func setup(sim_world: SimWorld, pc_device_id: int) -> void:
	world = sim_world
	pc_id = pc_device_id
	layer = 10
	visible = false
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_stylebox_override("panel", UiStyle.panel(Color("#16202B"), 0, 0))
	add_child(_root)
	var column := VBoxContainer.new()
	_root.add_child(column)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.panel(Color("#0F1720"), 0, 8))
	column.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	bar_row.add_child(UiStyle.label("HomeLab OS", 18, UiStyle.HIGHLIGHT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(spacer)
	_credits = UiStyle.label("", 16, UiStyle.MUSTARD)
	bar_row.add_child(_credits)
	_clock = UiStyle.label("", 16)
	bar_row.add_child(_clock)
	bar_row.add_child(UiStyle.button(TranslationServer.translate("Levantarse (Esc)"), close))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var apps := VBoxContainer.new()
	apps.custom_minimum_size = Vector2(170, 0)
	body.add_child(apps)
	apps.add_child(UiStyle.label(TranslationServer.translate("Aplicaciones"), 14, UiStyle.MIST))
	apps.add_child(UiStyle.button(TranslationServer.translate("Tienda"), show_page.bind(&"shop")))
	apps.add_child(UiStyle.button(TranslationServer.translate("Pedidos"), show_page.bind(&"orders")))
	apps.add_child(UiStyle.button(TranslationServer.translate("Terminal"), show_page.bind(&"terminal")))
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	body.add_child(margin)
	_content = VBoxContainer.new()
	margin.add_child(_content)


func open() -> void:
	visible = true
	if _page == &"":
		show_page(&"shop")
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"close_interaction"):
		get_viewport().set_input_as_handled()
		close()


func show_page(page: StringName) -> void:
	_page = page
	for child: Node in _content.get_children():
		if child != _terminal:
			child.queue_free()
	if _terminal != null:
		_terminal.visible = page == &"terminal"
	match page:
		&"shop":
			_build_shop()
		&"orders":
			_build_orders()
		&"terminal":
			if _terminal == null:
				_terminal = TerminalView.new()
				_terminal.setup(world, pc_id, world.get_device(pc_id).host.login_user)
				_terminal.exit_requested.connect(show_page.bind(&"shop"))
				_content.add_child(_terminal)
			_terminal.visible = true
			_terminal.focus_input.call_deferred()
	refresh()


func refresh() -> void:
	if not visible:
		return
	_clock.text = "   " + world.clock_text() + "   "
	_credits.text = TranslationServer.translate("%d créditos") % world.credits


# -------------------------------------------------------------------- shop --

func _build_shop() -> void:
	_content.add_child(UiStyle.label(TranslationServer.translate("Tienda Rackwell & Cía. — material para tu homelab"), 22))
	if not NetworkEngine.has_internet(world, world.get_device(pc_id)):
		_content.add_child(UiStyle.label(TranslationServer.translate("Sin conexión: el ordenador no llega a Internet. Revisa el cable y el router."), 16, UiStyle.BAD))
		return
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for def: HardwareDefinition in world.catalog.purchasable_items():
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.panel(Color("#22303D"), 6, 10))
		list.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiStyle.label(def.display_name(), 17))
		var desc := UiStyle.label(def.description, 13, UiStyle.MIST)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		row.add_child(UiStyle.label(TranslationServer.translate("%d cr") % def.price, 17, UiStyle.MUSTARD))
		row.add_child(UiStyle.button(TranslationServer.translate("Añadir"), _add_to_cart.bind(def.id)))
	var cart_panel := PanelContainer.new()
	cart_panel.custom_minimum_size = Vector2(300, 0)
	cart_panel.add_theme_stylebox_override("panel", UiStyle.panel(Color("#22303D"), 6, 12))
	columns.add_child(cart_panel)
	var cart_box := VBoxContainer.new()
	cart_panel.add_child(cart_box)
	cart_box.add_child(UiStyle.label(TranslationServer.translate("Carrito"), 19))
	var total := 0
	for i: int in _cart.size():
		var def := world.catalog.get_item(_cart[i])
		total += def.price
		var line := HBoxContainer.new()
		var name_label := UiStyle.label("%s — %d cr" % [def.display_name(), def.price], 14)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		line.add_child(UiStyle.button("×", _remove_from_cart.bind(i)))
		cart_box.add_child(line)
	if _cart.is_empty():
		cart_box.add_child(UiStyle.label(TranslationServer.translate("Vacío. Añade productos de la lista."), 14, UiStyle.MIST))
	cart_box.add_child(UiStyle.label(TranslationServer.translate("Total: %d créditos") % total, 17, UiStyle.MUSTARD))
	cart_box.add_child(UiStyle.button(TranslationServer.translate("Comprar"), _buy, _cart.is_empty()))
	_message = UiStyle.label("", 14, UiStyle.OK)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cart_box.add_child(_message)


func _add_to_cart(item_id: StringName) -> void:
	_cart.append(item_id)
	show_page(&"shop")


func _remove_from_cart(index: int) -> void:
	_cart.remove_at(index)
	show_page(&"shop")


func _buy() -> void:
	var r := world.purchase(_cart)
	if r.ok:
		_cart.clear()
	show_page(&"shop")
	_message.text = r.message
	_message.add_theme_color_override("font_color", UiStyle.OK if r.ok else UiStyle.BAD)


# ------------------------------------------------------------------ orders --

func _build_orders() -> void:
	_content.add_child(UiStyle.label(TranslationServer.translate("Mis pedidos"), 22))
	if world.orders.is_empty():
		_content.add_child(UiStyle.label(TranslationServer.translate("Todavía no has pedido nada. Abre la Tienda."), 15, UiStyle.MIST))
		return
	var pending := false
	for order: Dictionary in world.orders:
		var names: Array[String] = []
		for group: Array in order["groups"]:
			names.append(world.get_device(group[0]).display_name())
		var state: String
		if order["delivered"]:
			state = TranslationServer.translate("Entregado: los paquetes están junto a la puerta.")
		else:
			pending = true
			state = TranslationServer.translate("En camino: llega en %s.") % SimWorld.format_duration(order["eta"] - world.time_minutes)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.panel(Color("#22303D"), 6, 10))
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(UiStyle.label(TranslationServer.translate("Pedido %d — %d créditos") % [order["id"], order["total"]], 16))
		box.add_child(UiStyle.label(", ".join(names), 14, UiStyle.MIST))
		box.add_child(UiStyle.label(state, 14, UiStyle.OK if order["delivered"] else UiStyle.WARN))
		_content.add_child(card)
	if pending:
		_content.add_child(UiStyle.button(TranslationServer.translate("Esperar hasta la entrega"), _wait_delivery))


func _wait_delivery() -> void:
	world.skip_to_next_event()
	show_page(&"orders")
