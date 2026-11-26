extends Control
## Игровой интерфейс боя: таймер, пауза и скорость, состояние сторон,
## переключатель выделения, подсказки, меню паузы и экран результата.
## Интерфейс строится в коде, чтобы сцена hud.tscn оставалась минимальной.

signal multi_mode_toggled(on: bool)
signal commands_requested
signal cancel_requested
signal world_map_requested
signal menu_requested
signal restart_requested

const GameClockScript := preload("res://scripts/battle/game_clock.gd")

var battle: Node = null
var clock: Node = null
var selection: RefCounted = null

var _title_label: Label
var _time_label: Label
var _speed_label: Label
var _status_label: Label
var _pause_btn: Button
var _speed_btns: Array = []
var _multi_btn: Button
var _cmd_btn: Button
var _cancel_btn: Button
var _hint_panel: PanelContainer
var _hint_label: Label
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween = null
var _pause_overlay: ColorRect
var _result_overlay: ColorRect
var _result_title: Label
var _result_info: Label
var _was_paused: bool = false
var _box: Rect2 = Rect2()
var _box_visible: bool = false
var _upd_timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_top()
	_build_bottom()
	_build_pause_menu()
	_build_result_screen()


func bind(p_battle: Node, p_clock: Node, p_selection: RefCounted) -> void:
	battle = p_battle
	clock = p_clock
	selection = p_selection
	_title_label.text = str(battle.scenario.get("name", ""))
	clock.paused_changed.connect(_on_paused_changed)
	clock.speed_changed.connect(_on_speed_changed)
	selection.changed.connect(_on_selection_changed)
	_refresh_labels()


# ---------------------------------------------------------------- построение

func _make_label(text: String, size: int = 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_button(text: String, min_w: float = 84.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _build_top() -> void:
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	add_child(top)

	var bar := PanelContainer.new()
	top.add_child(bar)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)

	_title_label = _make_label("", 16)
	_title_label.custom_minimum_size = Vector2(180, 0)
	_title_label.clip_text = true
	hb.add_child(_title_label)

	_time_label = _make_label("00:00", 22)
	hb.add_child(_time_label)
	_speed_label = _make_label("", 16)
	hb.add_child(_speed_label)
	_status_label = _make_label("", 16)
	hb.add_child(_status_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(spacer)

	_pause_btn = _make_button("Пауза", 96)
	_pause_btn.pressed.connect(func(): clock.toggle_pause())
	hb.add_child(_pause_btn)

	var group := ButtonGroup.new()
	for i in GameClockScript.SPEEDS.size():
		var b := _make_button("x%d" % int(GameClockScript.SPEEDS[i]), 62)
		b.toggle_mode = true
		b.button_group = group
		b.pressed.connect(_on_speed_pressed.bind(i))
		hb.add_child(b)
		_speed_btns.append(b)
	_speed_btns[0].button_pressed = true

	var menu_btn := _make_button("Меню", 84)
	menu_btn.pressed.connect(toggle_pause_menu)
	hb.add_child(menu_btn)

	_hint_panel = PanelContainer.new()
	_hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	_hint_label = _make_label("", 20)
	_hint_panel.add_child(_hint_label)
	top.add_child(_hint_panel)

	_toast_panel = PanelContainer.new()
	_toast_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	_toast_label = _make_label("", 18)
	_toast_panel.add_child(_toast_label)
	top.add_child(_toast_panel)

	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, 8)


func _build_bottom() -> void:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)

	_multi_btn = _make_button("Выбор: один", 190)
	_multi_btn.toggle_mode = true
	_multi_btn.toggled.connect(_on_multi_toggled)
	hb.add_child(_multi_btn)

	_cmd_btn = _make_button("Команды", 150)
	_cmd_btn.pressed.connect(func(): commands_requested.emit())
	hb.add_child(_cmd_btn)

	_cancel_btn = _make_button("Отмена", 120)
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(func(): cancel_requested.emit())
	hb.add_child(_cancel_btn)

	add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)


## Создаёт затемнение с центральной панелью. Возвращает [overlay, vbox].
func _make_modal() -> Array:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(380, 0)
	margin.add_child(vb)
	return [overlay, vb]


func _build_pause_menu() -> void:
	var parts := _make_modal()
	_pause_overlay = parts[0]
	var vb: VBoxContainer = parts[1]
	var title := _make_label("Пауза", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var resume := _make_button("Продолжить", 200)
	resume.pressed.connect(toggle_pause_menu)
	vb.add_child(resume)
	var world := _make_button("Глобальная карта", 200)
	world.pressed.connect(func(): world_map_requested.emit())
	vb.add_child(world)
	var menu := _make_button("Главное меню", 200)
	menu.pressed.connect(func(): menu_requested.emit())
	vb.add_child(menu)


func _build_result_screen() -> void:
	var parts := _make_modal()
	_result_overlay = parts[0]
	var vb: VBoxContainer = parts[1]
	_result_title = _make_label("", 34)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_result_title)
	_result_info = _make_label("", 18)
	_result_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_result_info)
	var world := _make_button("На глобальную карту", 200)
	world.pressed.connect(func(): world_map_requested.emit())
	vb.add_child(world)
	var again := _make_button("Повторить сценарий", 200)
	again.pressed.connect(func(): restart_requested.emit())
	vb.add_child(again)
	var menu := _make_button("Главное меню", 200)
	menu.pressed.connect(func(): menu_requested.emit())
	vb.add_child(menu)


# ---------------------------------------------------------------- публичные методы

func set_box(rect: Rect2, visible_box: bool) -> void:
	_box = rect
	_box_visible = visible_box
	queue_redraw()


func show_hint(text: String) -> void:
	_hint_label.text = text
	_hint_panel.visible = true


func hide_hint() -> void:
	_hint_panel.visible = false


func set_cancel_visible(v: bool) -> void:
	_cancel_btn.visible = v


func toast(text: String) -> void:
	_toast_label.text = text
	_toast_panel.visible = true
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.8)
	_toast_tween.tween_callback(func(): _toast_panel.visible = false)


func toggle_pause_menu() -> void:
	if _result_overlay.visible:
		return
	if _pause_overlay.visible:
		_pause_overlay.visible = false
		clock.set_paused(_was_paused)
	else:
		_was_paused = clock.paused
		clock.set_paused(true)
		_pause_overlay.visible = true


func show_result(result: Dictionary) -> void:
	_pause_overlay.visible = false
	var outcome := str(result.get("outcome", "draw"))
	match outcome:
		"victory":
			_result_title.text = "ПОБЕДА"
		"defeat":
			_result_title.text = "ПОРАЖЕНИЕ"
		_:
			_result_title.text = "НИЧЬЯ"
	_result_info.text = "%s\nВремя матча: %s\nПотери: свои %d, противника %d\nРезультат сохранён и применён к глобальной карте." % [
		str(result.get("reason", "")), GameClockScript.format_time(float(result.get("time", 0.0))),
		int(result.get("losses_own", 0)), int(result.get("losses_enemy", 0))]
	_result_overlay.visible = true


# ---------------------------------------------------------------- обновление

func _process(delta: float) -> void:
	if battle == null:
		return
	_upd_timer -= delta
	if _upd_timer <= 0.0:
		_upd_timer = 0.2
		_refresh_labels()


func _refresh_labels() -> void:
	var t: String = GameClockScript.format_time(clock.elapsed)
	var left: float = battle.rules.get_time_left(clock.elapsed)
	if left >= 0.0:
		t += " / " + GameClockScript.format_time(battle.rules.time_limit)
	_time_label.text = t

	if clock.paused:
		_speed_label.text = "ПАУЗА"
	elif clock.speed_index == 0:
		_speed_label.text = "Реальное время"
	else:
		_speed_label.text = "Ускорение x%d" % int(GameClockScript.SPEEDS[clock.speed_index])

	var mine: int = battle.count_units(battle.player_faction)
	var total := 0
	for u in battle.units:
		if is_instance_valid(u) and u.alive:
			total += 1
	var owned := 0
	for p in battle.points:
		if p.owner_id == battle.player_faction:
			owned += 1
	_status_label.text = "Свои: %d  Противник: %d  Точки: %d/%d" % [mine, total - mine, owned, battle.points.size()]


func _on_paused_changed(paused: bool) -> void:
	_pause_btn.text = "Пуск" if paused else "Пауза"
	_refresh_labels()


func _on_speed_pressed(index: int) -> void:
	clock.set_speed_index(index)


func _on_speed_changed(index: int) -> void:
	if index < _speed_btns.size():
		_speed_btns[index].set_pressed_no_signal(true)
	_refresh_labels()


func _on_multi_toggled(on: bool) -> void:
	_multi_btn.text = "Выбор: рамка" if on else "Выбор: один"
	multi_mode_toggled.emit(on)


func _on_selection_changed(units: Array) -> void:
	_cmd_btn.text = "Команды (%d)" % units.size() if units.size() > 0 else "Команды"


func _draw() -> void:
	if _box_visible:
		draw_rect(_box, Color(0.3, 0.7, 1.0, 0.15))
		draw_rect(_box, Color(0.4, 0.8, 1.0, 0.9), false, 2.0)
