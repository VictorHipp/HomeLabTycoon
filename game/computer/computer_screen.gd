class_name ComputerScreen
extends CanvasLayer
## The in-world computer's desktop, "HomeLab OS" (docs/TERMINAL_DESIGN.md §2): Shop, Second hand,
## My account, Orders and Terminal. Shown full screen once the camera reaches the monitor
## (docs/INTERACTION_SYSTEM.md §6: the prototype uses the full-screen variant; the shared
## SubViewport is spike S2). Each app is built once and kept (the basket survives switching).

signal closed
signal menu_requested
signal message_shown(ok: bool) ## An app showed a result (false = something was refused).

const APPS := [["shop", "Tienda"], ["market", "Segunda mano"], ["account", "Mi cuenta"], ["orders", "Pedidos"], ["terminal", "Terminal"]]

var world: SimWorld
var pc_id: int = -1
var shop: ShopApp
var market: MarketApp
var account: AccountApp
var _root: PanelContainer
var _content: MarginContainer
var _orders: VBoxContainer
var _clock: Label
var _credits: Label
var _page: StringName = &""
var _terminal: TerminalView = null
var _app_buttons: Dictionary = {}
var _dirty: bool = false


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
	bar_row.add_child(UiStyle.button(TranslationServer.translate("Menú"), func() -> void: menu_requested.emit()))
	bar_row.add_child(UiStyle.button(TranslationServer.translate("Levantarse (Esc)"), close))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var apps := VBoxContainer.new()
	apps.custom_minimum_size = Vector2(170, 0)
	body.add_child(apps)
	apps.add_child(UiStyle.label(TranslationServer.translate("Aplicaciones"), 14, UiStyle.MIST))
	for app: Array in APPS:
		var b := UiStyle.button(TranslationServer.translate(app[1]), show_page.bind(StringName(app[0])))
		b.toggle_mode = true
		apps.add_child(b)
		_app_buttons[StringName(app[0])] = b
	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side, 12)
	body.add_child(_content)
	shop = ShopApp.new()
	shop.setup(world, pc_id)
	shop.message_shown.connect(func(_text: String, ok: bool) -> void: message_shown.emit(ok))
	_content.add_child(shop)
	market = MarketApp.new()
	market.setup(world)
	market.message_shown.connect(func(_text: String, ok: bool) -> void: message_shown.emit(ok))
	_content.add_child(market)
	account = AccountApp.new()
	account.setup(world)
	_content.add_child(account)
	_orders = VBoxContainer.new()
	_orders.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_orders)
	for page: Control in [shop, market, account, _orders]:
		page.visible = false
	world.event_emitted.connect(func(_type: StringName, _data: Dictionary) -> void: _dirty = true)


func open() -> void:
	visible = true
	if _page == &"":
		show_page(&"shop")
	else:
		show_page(_page)
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
	for key: StringName in _app_buttons:
		(_app_buttons[key] as Button).button_pressed = key == page
	shop.visible = page == &"shop"
	market.visible = page == &"market"
	account.visible = page == &"account"
	_orders.visible = page == &"orders"
	if _terminal != null:
		_terminal.visible = page == &"terminal"
	match page:
		&"shop":
			shop.show_list()
		&"market":
			market.rebuild()
		&"account":
			account.rebuild()
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
	_dirty = false
	refresh()


## Called a few times per second: header, and pages that show live state are rebuilt after a
## change in the world (deliveries, income, sales). The shop keeps its page and scroll.
func refresh() -> void:
	if not visible:
		return
	_clock.text = "   " + world.clock_text() + "   "
	_credits.text = TranslationServer.translate("%d créditos") % world.credits
	shop.refresh_balance()
	if _dirty:
		_dirty = false
		match _page:
			&"account":
				account.rebuild()
			&"orders":
				_build_orders()
			&"market":
				market.rebuild()


# ------------------------------------------------------------------ orders --

func _build_orders() -> void:
	for child: Node in _orders.get_children():
		_orders.remove_child(child)
		child.queue_free()
	_orders.add_child(UiStyle.label(TranslationServer.translate("Mis pedidos"), 22))
	if world.orders.is_empty():
		_orders.add_child(UiStyle.label(TranslationServer.translate("Todavía no has pedido nada. Abre la Tienda."), 15, UiStyle.MIST))
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_orders.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var pending := false
	var newest_first := world.orders.duplicate()
	newest_first.reverse()
	for order: Dictionary in newest_first:
		var names: Array[String] = []
		for group: Array in order["groups"]:
			for device_id: int in group:
				names.append(world.get_device(device_id).display_name())
		var state: String
		if order["delivered"]:
			state = TranslationServer.translate("Entregado: las cajas están en la zona de entregas, junto a la puerta.")
		else:
			pending = true
			state = TranslationServer.translate("En camino: llega en %s.") % SimWorld.format_duration(order["eta"] - world.time_minutes)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiStyle.panel(Color("#22303D"), 6, 10))
		var box := VBoxContainer.new()
		card.add_child(box)
		box.add_child(UiStyle.label(TranslationServer.translate("Pedido %d — %d créditos") % [order["id"], order["total"]], 16))
		var items := UiStyle.label(", ".join(names), 14, UiStyle.MIST)
		items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(items)
		box.add_child(UiStyle.label(state, 14, UiStyle.OK if order["delivered"] else UiStyle.WARN))
		list.add_child(card)
	if pending:
		_orders.add_child(UiStyle.button(TranslationServer.translate("Esperar hasta la entrega"), _wait_delivery))


func _wait_delivery() -> void:
	world.skip_to_next_event()
	show_page(&"orders")
