extends Control
## Главное меню. Интерфейс строится в коде.

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#111827")
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.custom_minimum_size = Vector2(440, 0)
	center.add_child(vb)

	var title := Label.new()
	title.text = "SVO GAME 22-26"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	vb.add_child(title)

	var version := Label.new()
	version.text = "Версия %s — технический фундамент" % str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 16)
	version.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(version)

	vb.add_child(_button("Тестовая карта (быстрый старт)", _on_test_map))
	vb.add_child(_button("Глобальная карта и сценарии", _on_world_map))
	vb.add_child(_button("Сбросить прогресс", _on_reset))
	vb.add_child(_button("Выход", _on_quit))

	var tip := Label.new()
	tip.text = "Касание подразделения — круговое меню. Щипок — масштаб. Перетаскивание — камера."
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 14)
	tip.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(tip)


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 60)
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


func _on_test_map() -> void:
	GameState.start_scenario("test_01", "side_a")


func _on_world_map() -> void:
	GameState.change_scene(GameState.SCENE_WORLD_MAP)


func _on_reset() -> void:
	GameState.reset_progress()


func _on_quit() -> void:
	get_tree().quit()
