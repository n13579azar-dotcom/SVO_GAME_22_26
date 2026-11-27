extends Control
## Экран глобальной карты: места сценариев, фильтр по годам, карточка места с датами,
## статусом проверки и источниками. Играть можно только сценарии, для которых создана боевая карта.

const STATUS_TEXT := {
	"verified": "Даты подтверждены источниками",
	"partial": "Даты подтверждены частично (источники расходятся)",
	"needs_check": "Требует проверки: даты и описание не сверены с источниками",
	"fictional": "Вымышленный тестовый сценарий",
}
const STATUS_COLOR := {
	"verified": Color("#86efac"), "partial": Color("#fde68a"),
	"needs_check": Color("#fca5a5"), "fictional": Color("#cbd5e1"),
}
const OUTCOME_NAMES := {"victory": "Победа", "defeat": "Поражение", "draw": "Ничья"}
const FILTERS := [["", "Все"], ["2014", "2014"], ["2022", "2022"], ["2023", "2023"], ["2024", "2024+"], ["test", "Тест"], ["none", "Без года"]]

@onready var view: Control = $Layout/WorldMapView
@onready var side_panel: PanelContainer = $Layout/SidePanel

var _info: VBoxContainer
var _side_box: HBoxContainer
var _start_btn: Button
var _panel_btn: Button
var _filter_buttons: Dictionary = {}

var _place_id: String = ""
var _scenario_id: String = ""
var _side_id: String = ""


func _ready() -> void:
	_build_panel()
	_build_panel_toggle()
	view.place_selected.connect(_on_place_selected)
	_apply_filter_ui()
	var last := GameState.last_place_id
	if last != "" and not DataLoader.get_place(last).is_empty():
		view.select_place(last)
		if GameState.map_camera.is_empty():
			view.focus_place(last)
		_show_place(last)
	else:
		_show_list()


func _build_panel() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	side_panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	outer.add_child(_label("Места сценариев", 24))

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	outer.add_child(flow)
	for f in FILTERS:
		var b := Button.new()
		b.text = str(f[1])
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_filter.bind(str(f[0])))
		flow.add_child(b)
		_filter_buttons[str(f[0])] = b

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 8)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.custom_minimum_size = Vector2(350, 0)
	scroll.add_child(_info)

	_side_box = HBoxContainer.new()
	_side_box.add_theme_constant_override("separation", 8)
	outer.add_child(_side_box)

	_start_btn = _button("Начать сценарий")
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start)
	outer.add_child(_start_btn)

	var back := _button("Назад в меню")
	back.pressed.connect(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
	outer.add_child(back)


func _build_panel_toggle() -> void:
	_panel_btn = Button.new()
	_panel_btn.text = "Панель"
	_panel_btn.custom_minimum_size = Vector2(110, 56)
	_panel_btn.add_theme_font_size_override("font_size", 18)
	_panel_btn.focus_mode = Control.FOCUS_NONE
	_panel_btn.position = Vector2(12, 12)
	_panel_btn.pressed.connect(func(): side_panel.visible = not side_panel.visible)
	view.add_child(_panel_btn)
	view.register_ui_blocker(_panel_btn)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------- фильтр и список

func _apply_filter_ui() -> void:
	for k in _filter_buttons.keys():
		(_filter_buttons[k] as Button).button_pressed = (str(k) == view.filter_key)


func _on_filter(key: String) -> void:
	view.set_filter(key)
	_apply_filter_ui()
	if _place_id == "" or not view.place_matches(DataLoader.get_place(_place_id), key):
		_show_list()


func _show_list() -> void:
	_place_id = ""
	_reset_play()
	_clear_children(_info)
	var shown := 0
	var unknown: Array = []
	var items: Array = []
	for pl in DataLoader.places:
		if not view.place_matches(pl, view.filter_key):
			continue
		if pl.get("pos", null) == null:
			unknown.append(pl)
		else:
			items.append(pl)
	items.sort_custom(func(a, b): return str(a.get("name", "")) < str(b.get("name", "")))
	_info.add_child(_label("Выберите маркер на карте или место из списка (%d)." % (items.size() + unknown.size()), 15))
	for pl in items:
		_info.add_child(_place_button(pl))
		shown += 1
	if not unknown.is_empty():
		var h := _label("Без подтверждённых координат (на карте не показаны):", 15)
		h.modulate = Color(1, 1, 1, 0.75)
		_info.add_child(h)
		for pl in unknown:
			_info.add_child(_place_button(pl))
	if shown == 0 and unknown.is_empty():
		_info.add_child(_label("Для этого фильтра мест нет.", 16))


func _place_button(pl: Dictionary) -> Button:
	var b := _button(str(pl.get("name", "")))
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(0, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(_on_list_pick.bind(str(pl.get("id", ""))))
	return b


func _on_list_pick(id: String) -> void:
	view.select_place(id)
	if DataLoader.get_place(id).get("pos", null) != null:
		view.focus_place(id)
	_show_place(id)


# ---------------------------------------------------------------- карточка места

func _on_place_selected(id: String) -> void:
	_show_place(id)


func _reset_play() -> void:
	_scenario_id = ""
	_side_id = ""
	_clear_children(_side_box)
	_start_btn.disabled = true


func _show_place(id: String) -> void:
	var pl := DataLoader.get_place(id)
	if pl.is_empty():
		_show_list()
		return
	_place_id = id
	GameState.last_place_id = id
	_reset_play()
	_clear_children(_info)

	var back := _button("← Список мест")
	back.custom_minimum_size = Vector2(0, 40)
	back.add_theme_font_size_override("font_size", 16)
	back.pressed.connect(func():
		view.select_place("")
		_show_list())
	_info.add_child(back)

	_info.add_child(_label(str(pl.get("name", id)), 24))
	var pos_status := str(pl.get("pos_status", ""))
	if pos_status == "approx":
		var l := _label("Положение на карте ориентировочное.", 14)
		l.modulate = Color(1, 1, 1, 0.65)
		_info.add_child(l)
	elif pos_status == "unknown":
		var l := _label("Координаты не подтверждены, на карте не показано.", 14)
		l.modulate = Color(1, 1, 1, 0.65)
		_info.add_child(l)

	for ev in pl.get("events", []):
		_info.add_child(HSeparator.new())
		_info.add_child(_label(str(ev.get("title", "")), 19))
		var status := str(ev.get("date_status", ""))
		var dl := _label(str(ev.get("date_label", "")), 16)
		_info.add_child(dl)
		var st := _label(str(STATUS_TEXT.get(status, status)), 14)
		st.modulate = STATUS_COLOR.get(status, Color.WHITE)
		_info.add_child(st)
		var summary := str(ev.get("summary", ""))
		if summary != "":
			_info.add_child(_label(summary, 15))
		var note := str(ev.get("note", ""))
		if note != "":
			var nl := _label(note, 13)
			nl.modulate = Color(1, 1, 1, 0.6)
			_info.add_child(nl)
		var srcs: Array = ev.get("sources", [])
		if not srcs.is_empty():
			_info.add_child(_label("Источники:", 14))
			for s in srcs:
				var link := LinkButton.new()
				link.text = str(s.get("title", ""))
				link.uri = str(s.get("url", ""))
				link.add_theme_font_size_override("font_size", 14)
				link.focus_mode = Control.FOCUS_NONE
				_info.add_child(link)
		var sid := str(ev.get("scenario_id", ""))
		var res := GameState.get_result(sid) if sid != "" else {}
		if not res.is_empty():
			_info.add_child(_label("Ваш результат: %s" % OUTCOME_NAMES.get(str(res.get("outcome", "")), "—"), 15))
		if sid != "" and not DataLoader.get_scenario(sid).is_empty():
			var pb := _button("Играть: " + str(ev.get("title", "")))
			pb.pressed.connect(_on_event_chosen.bind(sid))
			_info.add_child(pb)
		else:
			var nb := _label("Боевой сценарий для этого события ещё не создан.", 14)
			nb.modulate = Color(1, 1, 1, 0.6)
			_info.add_child(nb)


func _on_event_chosen(sid: String) -> void:
	_scenario_id = sid
	var scn := DataLoader.get_scenario(sid)
	_clear_children(_side_box)
	_side_id = ""
	var group := ButtonGroup.new()
	for side in scn.get("sides", []):
		if not bool(side.get("playable", true)):
			continue
		var fid := str(side.get("faction", ""))
		var b := _button(DataLoader.get_faction_name(fid))
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_side_chosen.bind(fid))
		_side_box.add_child(b)
		if _side_id == "":
			b.button_pressed = true
			_side_id = fid
	_start_btn.disabled = _side_id == ""


func _on_side_chosen(fid: String) -> void:
	_side_id = fid
	_start_btn.disabled = _scenario_id == ""


func _on_start() -> void:
	if _scenario_id != "" and _side_id != "":
		GameState.start_scenario(_scenario_id, _side_id)
