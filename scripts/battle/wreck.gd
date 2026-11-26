extends Node2D
## Обломки уничтоженного подразделения: крест, который постепенно гаснет.

var color: Color = Color.WHITE
var radius: float = 14.0
var lifetime: float = 25.0
var _age: float = 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := 1.0 - _age / lifetime
	var c := Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.75 * k)
	var r := radius * 0.8
	draw_line(Vector2(-r, -r), Vector2(r, r), c, 3.0)
	draw_line(Vector2(-r, r), Vector2(r, -r), c, 3.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 20, Color(0.1, 0.1, 0.1, 0.5 * k), 2.0)
