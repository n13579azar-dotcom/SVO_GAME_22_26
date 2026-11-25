extends Node
## Игровые часы матча: пауза, реальная скорость (x1), ускорение (x2, x4, x8).
## Время симуляции (elapsed) идёт только пока игра не на паузе.

signal paused_changed(paused: bool)
signal speed_changed(index: int)

const SPEEDS: Array = [1.0, 2.0, 4.0, 8.0]

var paused: bool = false
var speed_index: int = 0
var elapsed: float = 0.0


func get_scale() -> float:
	return 0.0 if paused else float(SPEEDS[speed_index])


func advance(dt: float) -> void:
	elapsed += dt


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	paused_changed.emit(paused)


func toggle_pause() -> void:
	set_paused(not paused)


func set_speed_index(index: int) -> void:
	index = clampi(index, 0, SPEEDS.size() - 1)
	speed_index = index
	speed_changed.emit(index)


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%02d:%02d" % [s / 60, s % 60]
