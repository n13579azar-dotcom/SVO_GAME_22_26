extends PanelContainer
## Отдельный интерфейс техники: сведения о машине и список доступных действий.

signal command_chosen(command_id: String)

const CommandDefs := preload("res://scripts/commands/command_defs.gd")

var _units: Array = []
var _title: Label
var _info: Label
var _list: VBoxContainer
var _upd: float = 0.0


func _ready() -> void:
	visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.custom_minimum_size = Vector2(230, 0)
	margin.add_child(vb)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	vb.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 16)
	vb.add_child(_info)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	vb.add_child(_list)

	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(0, 46)
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_panel)
	vb.add_child(close)

	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 12)


func open_panel(units: Array, command_ids: Array) -> void:
	_units = units
	for c in _list.get_children():
		c.queue_free()
	for id in command_ids:
		var def := CommandDefs.get_def(id)
		var b := Button.new()
		b.text = str(def.get("label", id))
		b.custom_minimum_size = Vector2(0, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func(): command_chosen.emit(id))
		_list.add_child(b)
	_refresh()
	visible = true
	reset_size()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 12)


func close_panel() -> void:
	visible = false
	_units = []


func _process(delta: float) -> void:
	if not visible:
		return
	_upd -= delta
	if _upd <= 0.0:
		_upd = 0.25
		_refresh()


func _refresh() -> void:
	var alive: Array = []
	for u in _units:
		if is_instance_valid(u) and u.alive:
			alive.append(u)
	if alive.is_empty():
		_title.text = "Техника"
		_info.text = ""
		return
	var first: Node2D = alive[0]
	var title := str(first.type_data.get("name", "Техника"))
	if alive.size() > 1:
		title += " x%d" % alive.size()
	_title.text = title
	var hp := 0.0
	var hp_max := 0.0
	var seats := 0
	var loaded := 0
	for u in alive:
		hp += u.hp
		hp_max += u.max_hp
		seats += u.capacity
		loaded += u.passengers.size()
	var text := "Состояние: %d%%" % int(round(hp / maxf(hp_max, 1.0) * 100.0))
	if seats > 0:
		text += "\nДесант: %d/%d" % [loaded, seats]
	_info.text = text
