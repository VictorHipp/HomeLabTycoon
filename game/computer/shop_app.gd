class_name ShopApp
extends VBoxContainer
## The shop of the in-game computer, "Rackwell & Cía." (docs/HARDWARE_CATALOG.md §4), laid out
## like the big online stores: a catalogue of cards (photo, title, rating, price, delivery), a
## product page (gallery, selling points, buy box with compatibility notes, specs table built
## from the catalog data, what comes in the box, description, rating breakdown and reviews) and a
## basket. Photos are renders of the game's own models (tools/capture_shop_photos.ps1); texts and
## reviews come from data/shop/ (ShopListing). Buying is a SimWorld command.

signal message_shown(text: String, ok: bool)

const PAGE_BG := Color("#EEF1F4")
const CARD_BG := Color("#FFFFFF")
const TEXT := Color("#1B1F24")
const SUBTLE := Color("#5B6470")
const LINK := Color("#0E7C86")
const PRICE := Color("#B3402A")
const IN_STOCK := Color("#2E7D32")
const BUY := Color("#F0B43C")
const BUY_DARK := Color("#E39A1E")
const CATEGORIES := [["", "Todo"], ["rack", "Racks"], ["server", "Servidores"], ["switch", "Redes"], ["cable", "Cables"]]
const PHOTO_DIR := "res://assets/shop"
const CARD_WIDTH := 300.0

var world: SimWorld
var pc_id: int = -1
var cart: Array[StringName] = []
var page: StringName = &"list" ## list | product | cart
var product: StringName = &""
var category: String = ""
var query: String = ""
var _photo: int = 1
var _body: VBoxContainer
var _cart_button: Button
var _balance: Label
var _status: Label
var _search: LineEdit


func setup(sim_world: SimWorld, pc_device_id: int) -> void:
	world = sim_world
	pc_id = pc_device_id
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)


## Path of photo `n` (1, 2) of an item; "" if there is none.
static func photo_path(item_id: StringName, n: int = 1) -> String:
	var path := "%s/%s_%d.png" % [PHOTO_DIR, item_id, n]
	return path if ResourceLoader.exists(path) else ""


static func photo(item_id: StringName, n: int = 1) -> Texture2D:
	var path := photo_path(item_id, n)
	return load(path) as Texture2D if path != "" else null


func show_list() -> void:
	page = &"list"
	rebuild()


func show_product(item_id: StringName) -> void:
	page = &"product"
	product = item_id
	_photo = 1
	rebuild()


func show_cart() -> void:
	page = &"cart"
	rebuild()


func rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_build_header()
	if not NetworkEngine.has_internet(world, world.get_device(pc_id)):
		var offline := _page_panel()
		offline.add_child(_label(TranslationServer.translate("Sin conexión: el ordenador no llega a Internet. Revisa el cable de red y el router."), 18, PRICE))
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UiStyle.panel(PAGE_BG, 0, 16))
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	scroll.add_child(bg)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.add_child(_body)
	match page:
		&"product":
			_build_product()
		&"cart":
			_build_cart()
		_:
			_build_list()


func refresh_balance() -> void:
	if _balance != null and is_instance_valid(_balance):
		_balance.text = TranslationServer.translate("Saldo: %d cr") % world.credits


# ------------------------------------------------------------------ header --

func _build_header() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.INK, 0, 10))
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	var logo := LinkButton.new()
	logo.text = "Rackwell & Cía."
	logo.underline = LinkButton.UNDERLINE_MODE_NEVER
	logo.add_theme_font_size_override("font_size", 22)
	logo.add_theme_color_override("font_color", UiStyle.MUSTARD)
	logo.add_theme_color_override("font_hover_color", BUY)
	logo.focus_mode = Control.FOCUS_NONE
	logo.pressed.connect(func() -> void:
		category = ""
		query = ""
		show_list())
	row.add_child(logo)
	_search = LineEdit.new()
	_search.placeholder_text = TranslationServer.translate("Buscar: servidor, switch, cable de 5 m…")
	_search.text = query
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(text: String) -> void:
		query = text.strip_edges()
		show_list())
	row.add_child(_search)
	row.add_child(_shop_button(TranslationServer.translate("Buscar"), func() -> void:
		query = _search.text.strip_edges()
		show_list()))
	_balance = UiStyle.label("", 15, UiStyle.BONE)
	row.add_child(_balance)
	refresh_balance()
	var total := _cart_total()
	_cart_button = _shop_button(TranslationServer.translate("Cesta (%d) · %d cr") % [cart.size(), total], show_cart, false, true)
	row.add_child(_cart_button)
	var nav := PanelContainer.new()
	nav.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GRAPHITE, 0, 6))
	add_child(nav)
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 6)
	nav.add_child(cats)
	for entry: Array in CATEGORIES:
		var b := UiStyle.button(TranslationServer.translate(entry[1]), func() -> void:
			category = entry[0]
			query = ""
			show_list())
		b.toggle_mode = true
		b.button_pressed = page == &"list" and category == entry[0] and query == ""
		cats.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cats.add_child(spacer)
	cats.add_child(UiStyle.label(TranslationServer.translate("Envío gratis · llega en %s de juego · pagas con créditos") % SimWorld.format_duration(SimWorld.DELIVERY_MINUTES), 13, UiStyle.MIST))


# -------------------------------------------------------------------- list --

func _build_list() -> void:
	var items := _filtered_items()
	var heading: String = TranslationServer.translate("Resultados para «%s»") % query if query != "" else TranslationServer.translate("Material para tu homelab")
	_body.add_child(_label(heading, 22, TEXT))
	_body.add_child(_label(TranslationServer.translate("%d productos") % items.size(), 13, SUBTLE))
	if items.is_empty():
		_body.add_child(_label(TranslationServer.translate("No hay productos que coincidan. Prueba con otra palabra."), 16, SUBTLE))
		return
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.columns = 3
	_body.add_child(grid)
	_body.resized.connect(func() -> void:
		if is_instance_valid(grid):
			grid.columns = clampi(int(_body.size.x / (CARD_WIDTH + 12.0)), 2, 5))
	for def: HardwareDefinition in items:
		grid.add_child(_card(def))


func _filtered_items() -> Array[HardwareDefinition]:
	var result: Array[HardwareDefinition] = []
	var words := query.to_lower().split(" ", false)
	for def: HardwareDefinition in world.catalog.purchasable_items():
		if category != "" and String(def.category) != category and not (category == "switch" and def.category == &"router"):
			continue
		var listing := world.catalog.get_listing(def.id)
		var haystack := (def.display_name() + " " + def.description + " " + (listing.title if listing != null else "")).to_lower()
		var all := true
		for word: String in words:
			all = all and haystack.contains(word)
		if all:
			result.append(def)
	return result


func _card(def: HardwareDefinition) -> Control:
	var listing := world.catalog.get_listing(def.id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiStyle.panel(CARD_BG, 8, 12))
	card.name = "Card_%s" % def.id
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var image := TextureButton.new()
	image.texture_normal = photo(def.id)
	image.ignore_texture_size = true
	image.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(0, 170)
	image.focus_mode = Control.FOCUS_NONE
	image.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	image.pressed.connect(show_product.bind(def.id))
	box.add_child(image)
	var title := _link(listing.title if listing != null else def.display_name(), show_product.bind(def.id), 15)
	box.add_child(title)
	box.add_child(_label(def.display_name(), 12, SUBTLE)) # short name: what the inventory shows
	if listing != null:
		box.add_child(_rating_row(listing, 13))
	var price_row := HBoxContainer.new()
	price_row.add_child(_label("%d cr" % def.price, 24, PRICE))
	box.add_child(price_row)
	box.add_child(_label(TranslationServer.translate("Envío gratis · llega en %s") % SimWorld.format_duration(SimWorld.DELIVERY_MINUTES), 12, SUBTLE))
	var owned := _owned(def.id)
	if owned > 0:
		box.add_child(_label(TranslationServer.translate("Ya tienes %d") % owned, 12, LINK))
	var add := _shop_button(TranslationServer.translate("Añadir a la cesta"), _add.bind(def.id), false, true)
	add.name = "Add_%s" % def.id
	box.add_child(add)
	return card


# ----------------------------------------------------------------- product --

func _build_product() -> void:
	var def := world.catalog.get_item(product)
	var listing := world.catalog.get_listing(product)
	_body.add_child(_link(TranslationServer.translate("◀ Volver a los resultados"), show_list, 14))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	_body.add_child(top)
	# Gallery.
	var gallery := VBoxContainer.new()
	gallery.custom_minimum_size = Vector2(360, 0)
	top.add_child(gallery)
	var main_panel := PanelContainer.new()
	main_panel.add_theme_stylebox_override("panel", UiStyle.panel(CARD_BG, 8, 8))
	gallery.add_child(main_panel)
	var main_photo := TextureRect.new()
	main_photo.name = "MainPhoto"
	main_photo.texture = photo(product, _photo)
	main_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	main_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	main_photo.custom_minimum_size = Vector2(360, 270)
	main_panel.add_child(main_photo)
	var thumbs := HBoxContainer.new()
	gallery.add_child(thumbs)
	for n: int in [1, 2]:
		var texture := photo(product, n)
		if texture == null:
			continue
		var thumb := TextureButton.new()
		thumb.texture_normal = texture
		thumb.ignore_texture_size = true
		thumb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		thumb.custom_minimum_size = Vector2(84, 63)
		thumb.focus_mode = Control.FOCUS_NONE
		thumb.modulate = Color.WHITE if n == _photo else Color(1, 1, 1, 0.55)
		thumb.pressed.connect(func() -> void:
			_photo = n
			rebuild())
		thumbs.add_child(thumb)
	# Title, rating, selling points.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	top.add_child(info)
	var title := _label(listing.title if listing != null else def.display_name(), 21, TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(title)
	info.add_child(_label(TranslationServer.translate("Marca: %s · Modelo: %s") % [def.brand, def.model], 13, LINK))
	if listing != null:
		info.add_child(_rating_row(listing, 15))
	info.add_child(HSeparator.new())
	info.add_child(_label("%d cr" % def.price, 28, PRICE))
	if listing != null:
		info.add_child(_label(TranslationServer.translate("Acerca de este producto"), 16, TEXT))
		for bullet: String in listing.bullets:
			var line := _label("•  " + bullet, 14, TEXT)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(line)
	# Buy box.
	var buy := PanelContainer.new()
	buy.custom_minimum_size = Vector2(250, 0)
	buy.add_theme_stylebox_override("panel", UiStyle.panel(CARD_BG, 8, 14))
	top.add_child(buy)
	var buy_box := VBoxContainer.new()
	buy_box.add_theme_constant_override("separation", 8)
	buy.add_child(buy_box)
	buy_box.add_child(_label("%d cr" % def.price, 24, PRICE))
	buy_box.add_child(_wrap(_label(TranslationServer.translate("Envío gratis: llega en %s de juego a la zona de entregas, junto a la puerta.") % SimWorld.format_duration(SimWorld.DELIVERY_MINUTES), 13, TEXT)))
	buy_box.add_child(_label(TranslationServer.translate("En stock"), 15, IN_STOCK))
	for note: Array in _compatibility(def):
		buy_box.add_child(_wrap(_label(note[0], 13, IN_STOCK if note[1] else PRICE)))
	buy_box.add_child(_shop_button(TranslationServer.translate("Añadir a la cesta"), _add.bind(def.id), false, true))
	buy_box.add_child(_shop_button(TranslationServer.translate("Comprar ya"), func() -> void:
		_add(def.id)
		show_cart(), false, true))
	buy_box.add_child(_wrap(_label(TranslationServer.translate("Vendido por Rackwell & Cía. · Si no lo usas, puedes revenderlo en «Segunda mano» por menos de lo que costó."), 12, SUBTLE)))
	# Specs, box, description, reviews.
	_body.add_child(_section(TranslationServer.translate("Especificaciones")))
	var specs := GridContainer.new()
	specs.columns = 2
	specs.add_theme_constant_override("h_separation", 24)
	specs.add_theme_constant_override("v_separation", 4)
	_body.add_child(specs)
	for row: Array in ShopSpecs.rows(world, def):
		specs.add_child(_label(row[0], 14, SUBTLE))
		var value := _label(row[1], 14, TEXT)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.custom_minimum_size = Vector2(420, 0)
		specs.add_child(value)
	_body.add_child(_section(TranslationServer.translate("En la caja")))
	_body.add_child(_label(ShopSpecs.in_the_box(world, def), 14, TEXT))
	if listing != null:
		_body.add_child(_section(TranslationServer.translate("Descripción")))
		_body.add_child(_wrap(_label(listing.description, 14, TEXT)))
		_build_reviews(listing)


func _build_reviews(listing: ShopListing) -> void:
	_body.add_child(_section(TranslationServer.translate("Opiniones de clientes")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	_body.add_child(row)
	var summary := VBoxContainer.new()
	summary.custom_minimum_size = Vector2(300, 0)
	row.add_child(summary)
	summary.add_child(_rating_row(listing, 20))
	summary.add_child(_label(TranslationServer.translate("%s de 5 · %d opiniones") % [_decimal(listing.rating()), listing.reviews.size()], 14, SUBTLE))
	for stars: int in [5, 4, 3, 2, 1]:
		var bar_row := HBoxContainer.new()
		bar_row.add_child(_label(TranslationServer.translate("%d estrellas") % stars, 13, LINK))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(150, 14)
		bar.show_percentage = false
		bar.max_value = listing.reviews.size()
		bar.value = listing.count_with(stars)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = StarRating.GOLD
		fill.set_corner_radius_all(3)
		var back := StyleBoxFlat.new()
		back.bg_color = Color("#DDE1E6")
		back.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		bar_row.add_child(bar)
		bar_row.add_child(_label("%d %%" % roundi(100.0 * listing.count_with(stars) / maxf(1.0, listing.reviews.size())), 13, SUBTLE))
		summary.add_child(bar_row)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	row.add_child(list)
	for review: Dictionary in listing.reviews:
		var card := VBoxContainer.new()
		card.add_child(_label(String(review["author"]), 14, TEXT))
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(StarRating.make(float(review["stars"]), 14))
		head.add_child(_label(String(review["title"]), 14, TEXT))
		card.add_child(head)
		var verified: String = TranslationServer.translate(" · Compra verificada") if bool(review["verified"]) else ""
		card.add_child(_label(TranslationServer.translate("Opinión escrita %s") % String(review["date"]) + verified, 12, PRICE if bool(review["verified"]) else SUBTLE))
		card.add_child(_wrap(_label(String(review["text"]), 14, TEXT)))
		list.add_child(card)
	_body.add_child(_label(TranslationServer.translate("Tienda y opiniones ficticias, como todo el catálogo del juego. Las cifras técnicas salen de los datos del juego."), 11, SUBTLE))


## Notes about what the player already owns: [text, good?].
func _compatibility(def: HardwareDefinition) -> Array:
	var notes: Array = []
	var racks: Array[SimDevice] = []
	for d: SimDevice in world.devices_of(&"rack"):
		if d.location in [&"placed", &"inventory"]:
			racks.append(d)
	if def.placement == &"rack":
		if racks.is_empty():
			notes.append([TranslationServer.translate("Se monta en un rack de 19\" y aún no tienes ninguno."), false])
		else:
			var best := 0
			for rack: SimDevice in racks:
				var spec := rack.definition.get_spec(RackSpec) as RackSpec
				var used := 0
				for m: SimDevice in world.mounted_in(rack):
					used += m.definition.mount_height_u
				best = maxi(best, spec.capacity_u - used)
			notes.append([TranslationServer.translate("Cabe en tu rack: tienes %dU libres y ocupa %dU.") % [best, def.mount_height_u], best >= def.mount_height_u])
	var cable := def.get_spec(CableSpec) as CableSpec
	if cable != null:
		var free := 0
		var kind := PortDefinition.Kind.RJ45 if cable.media == &"copper" else PortDefinition.Kind.POWER_C13
		for d: SimDevice in world.devices.values():
			if not d.is_in_world():
				continue
			for ref: String in d.port_refs():
				if not world.port_cable.has(ref) and d.definition.find_port_group(PortRef.group(ref)).kind == kind:
					free += 1
		if cable.media == &"copper":
			notes.append([TranslationServer.translate("Puertos RJ45 libres en tus equipos instalados: %d.") % free, free > 0])
		else:
			notes.append([TranslationServer.translate("Tomas libres en tu regleta: %d.") % free, free > 0])
	elif def.find_port_group(&"psu") != null:
		var outlets := 0
		for strip: SimDevice in world.devices_of(&"power"):
			for ref: String in strip.port_refs():
				if not world.port_cable.has(ref):
					outlets += 1
		notes.append([TranslationServer.translate("Necesita una toma de corriente: tu regleta tiene %d libres.") % outlets, outlets > 0])
	if def.placement == &"floor" and def.get_spec(RackSpec) != null:
		var rack_spec := def.get_spec(RackSpec) as RackSpec
		notes.append([TranslationServer.translate("Ocupa %s × %s cm de suelo y pide %d cm libres delante y detrás.") % [
			_decimal(def.footprint_m.x * 100.0, 0), _decimal(def.footprint_m.y * 100.0, 0), roundi(rack_spec.service_clearance_m * 100.0)], true])
	return notes


# -------------------------------------------------------------------- cart --

func _build_cart() -> void:
	_body.add_child(_link(TranslationServer.translate("◀ Seguir comprando"), show_list, 14))
	_body.add_child(_label(TranslationServer.translate("Tu cesta"), 24, TEXT))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(CARD_BG, 8, 14))
	_body.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	if cart.is_empty():
		box.add_child(_label(TranslationServer.translate("Tu cesta está vacía. Añade productos desde el catálogo."), 16, SUBTLE))
	var counts := {}
	var order: Array[StringName] = []
	for item_id: StringName in cart:
		if not counts.has(item_id):
			counts[item_id] = 0
			order.append(item_id)
		counts[item_id] += 1
	for item_id: StringName in order:
		var def := world.catalog.get_item(item_id)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var thumb := TextureRect.new()
		thumb.texture = photo(item_id)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.custom_minimum_size = Vector2(96, 72)
		line.add_child(thumb)
		var name_box := VBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_child(_link(def.display_name(), show_product.bind(item_id), 15))
		name_box.add_child(_label(TranslationServer.translate("%d cr la unidad") % def.price, 13, SUBTLE))
		line.add_child(name_box)
		line.add_child(_shop_button("−", _remove.bind(item_id)))
		line.add_child(_label("%d" % counts[item_id], 16, TEXT))
		line.add_child(_shop_button("+", _add.bind(item_id)))
		line.add_child(_label("%d cr" % (def.price * int(counts[item_id])), 17, PRICE))
		box.add_child(line)
	box.add_child(HSeparator.new())
	var total := _cart_total()
	box.add_child(_label(TranslationServer.translate("Total: %d cr") % total, 20, TEXT))
	var after := world.credits - total
	box.add_child(_label(TranslationServer.translate("Tu saldo: %d cr · después del pedido: %d cr") % [world.credits, after], 14, IN_STOCK if after >= 0 else PRICE))
	box.add_child(_label(TranslationServer.translate("Cada equipo llega en su caja con sus accesorios; los cables sueltos, juntos en otra caja."), 13, SUBTLE))
	var pay := _shop_button(TranslationServer.translate("Tramitar pedido"), _buy, cart.is_empty() or after < 0, true)
	pay.name = "Pay"
	box.add_child(pay)
	_status = _label("", 15, IN_STOCK)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _add(item_id: StringName) -> void:
	cart.append(item_id)
	var def := world.catalog.get_item(item_id)
	var text: String = TranslationServer.translate("Añadido a la cesta: %s") % def.display_name()
	message_shown.emit(text, true)
	if page == &"cart":
		rebuild()
	else:
		# The catalogue keeps its place (no rebuild): only the basket button changes.
		_cart_button.text = TranslationServer.translate("Cesta (%d) · %d cr") % [cart.size(), _cart_total()]


func _remove(item_id: StringName) -> void:
	var i := cart.rfind(item_id)
	if i >= 0:
		cart.remove_at(i)
	rebuild()


func _buy() -> void:
	var r := world.purchase(cart)
	if r.ok:
		cart.clear()
	rebuild()
	if _status != null:
		_status.text = r.message
		_status.add_theme_color_override("font_color", IN_STOCK if r.ok else PRICE)
	message_shown.emit(r.message, r.ok)


## Last message of the basket page (for the automated walkthrough).
func status_text() -> String:
	return _status.text if _status != null and is_instance_valid(_status) else ""


func _cart_total() -> int:
	var total := 0
	for item_id: StringName in cart:
		total += world.catalog.get_item(item_id).price
	return total


func _owned(item_id: StringName) -> int:
	var n := 0
	for d: SimDevice in world.devices.values():
		if d.definition.id == item_id and not (d.location in [&"sold", &"in_transit"]):
			n += 1
	return n


# ----------------------------------------------------------------- widgets --

func _page_panel() -> VBoxContainer:
	var bg := PanelContainer.new()
	bg.add_theme_stylebox_override("panel", UiStyle.panel(PAGE_BG, 0, 20))
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(bg)
	var box := VBoxContainer.new()
	bg.add_child(box)
	return box


func _rating_row(listing: ShopListing, size: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(StarRating.make(listing.rating(), size))
	row.add_child(_label("%s (%d)" % [_decimal(listing.rating()), listing.reviews.size()], size - 1, LINK))
	return row


func _section(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	box.add_child(_label(text, 19, TEXT))
	return box


func _label(text: String, size: int, color: Color) -> Label:
	return UiStyle.label(text, size, color)


func _wrap(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(200, 0)
	return label


## A link: a flat button with link colours (LinkButton cannot wrap long titles).
func _link(text: String, callback: Callable, size: int) -> Button:
	var link := Button.new()
	link.text = text
	link.flat = true
	link.focus_mode = Control.FOCUS_NONE
	link.alignment = HORIZONTAL_ALIGNMENT_LEFT
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.add_theme_font_size_override("font_size", size)
	for color_name: String in ["font_color", "font_focus_color"]:
		link.add_theme_color_override(color_name, LINK)
	for color_name: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		link.add_theme_color_override(color_name, PRICE)
	link.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	link.custom_minimum_size = Vector2(200, 0)
	link.pressed.connect(callback)
	return link


## Shop buttons: a rounded yellow button for buying actions, plain otherwise.
func _shop_button(text: String, callback: Callable, disabled: bool = false, primary: bool = false) -> Button:
	var b := UiStyle.button(text, callback, disabled)
	if primary:
		for state: Array in [["normal", BUY], ["hover", BUY_DARK], ["pressed", BUY_DARK], ["disabled", Color("#D9D2C2")]]:
			var box := UiStyle.panel(state[1], 16, 8)
			b.add_theme_stylebox_override(state[0], box)
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(color_name, TEXT)
		b.add_theme_color_override("font_disabled_color", SUBTLE)
	return b


static func _decimal(value: float, decimals: int = 1) -> String:
	if decimals <= 0:
		return str(roundi(value))
	return ("%.1f" % value).replace(".", ",")
