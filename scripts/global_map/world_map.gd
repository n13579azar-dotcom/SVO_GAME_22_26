extends Control
## Экран глобальной карты: выбор территории, сценария и стороны конфликта.

const OUTCOME_NAMES := {"victory": "Победа", "defeat": "Поражение", "draw": "Ничья"}
const CONTROL_NAMES := {"controlled": "Под контролем", "contested": "Спорная", "neutral": "Нейтральная"}

@onready var view: Control = $Layout/WorldMapView

var _name_label: Label
var _owner_label: Label
var _scn_box: VBoxContainer
var _scn_desc: Label
var _side_box: HBoxContainer
var _start_btn: Button

var _territory_id: String = ""
var _scenario_id: String = ""
var _side_id: String = ""


func _ready() -> void:
	_build_panel()
	view.territory_selected.connect(_on_territory_selected)
	_clear_selection_ui()


func _build_panel() -> void:
	var side_panel: PanelContainer = $Layout/SidePanel
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	side_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var title := _label("Глобальная карта", 26)
	vb.add_child(title)
	_name_label = _label("Выберите территорию", 22)
	vb.add_child(_name_label)
	_owner_label = _label("", 16)
	vb.add_child(_owner_label)

	vb.add_child(_label("Сценарии:", 18))
	_scn_box = VBoxContainer.new()
	_scn_box.add_theme_constant_override("separation", 6)
	vb.add_child(_scn_box)

	_scn_desc = _label("", 15)
	_scn_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_scn_desc)

	vb.add_child(_label("Играть за:", 18))
	_side_box = HBoxContainer.new()
	_side_box.add_theme_constant_override("separation", 8)
	vb.add_child(_side_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	_start_btn = _button("Начать сценарий")
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start)
	vb.add_child(_start_btn)

	var back := _button("Назад в меню")
	back.pressed.connect(func(): GameState.change_scene(GameState.SCENE_MAIN_MENU))
	vb.add_child(back)


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
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
		c.queue_free()


func _clear_selection_ui() -> void:
	_scenario_id = ""
	_side_id = ""
	_clear_children(_scn_box)
	_clear_children(_side_box)
	_scn_desc.text = ""
	_start_btn.disabled = true


func _on_territory_selected(id: String) -> void:
	_territory_id = id
	_clear_selection_ui()
	var t := DataLoader.get_territory(id)
	var st := GameState.get_territory_state(id)
	_name_label.text = str(t.get("name", id))
	_owner_label.text = "Владелец: %s\nСостояние: %s" % [
		DataLoader.get_faction_name(str(st.get("owner", "neutral"))),
		CONTROL_NAMES.get(str(st.get("control", "neutral")), "—")]

	var scenarios: Array = t.get("scenarios", [])
	if scenarios.is_empty():
		_scn_desc.text = "Для этой территории пока нет сценариев."
		return
	for sid in scenarios:
		var scn := DataLoader.get_scenario(str(sid))
		if scn.is_empty():
			continue
		var text := str(scn.get("name", sid))
		var res := GameState.get_result(str(sid))
		if not res.is_empty():
			text += " [%s]" % OUTCOME_NAMES.get(str(res.get("outcome", "")), "—")
		var b := _button(text)
		b.pressed.connect(_on_scenario_chosen.bind(str(sid)))
		_scn_box.add_child(b)


func _on_scenario_chosen(sid: String) -> void:
	_scenario_id = sid
	var scn := DataLoader.get_scenario(sid)
	var kind := "Исторический" if str(scn.get("kind", "")) == "historical" else "Вымышленный"
	_scn_desc.text = "%s сценарий. %s\n%s" % [kind, str(scn.get("date_label", "")), str(scn.get("description", ""))]

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
