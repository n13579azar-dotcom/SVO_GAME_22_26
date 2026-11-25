extends Node2D
## Метка точки назначения: кольцо, которое расширяется и затухает.

var color: Color = Color.WHITE
var _t: float = 0.0
const LIFETIME := 0.8


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / LIFETIME
	var c := Color(color.r, color.g, color.b, 1.0 - k)
	draw_arc(Vector2.ZERO, 10.0 + 26.0 * k, 0.0, TAU, 24, c, 3.0)
	draw_circle(Vector2.ZERO, 4.0, c)
