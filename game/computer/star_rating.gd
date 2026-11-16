class_name StarRating
extends Control
## Five stars filled to `value` (0–5, in halves), drawn as polygons so they never depend on a
## font having the ★ glyph.

const GOLD := Color("#E8A317")
const EMPTY := Color("#C9CED6")

var value: float = 0.0
var star_size: float = 14.0


static func make(rating: float, size: float = 14.0) -> StarRating:
	var stars := StarRating.new()
	stars.value = rating
	stars.star_size = size
	stars.custom_minimum_size = Vector2(size * 5.0 + 8.0, size)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stars


func _draw() -> void:
	var r := star_size / 2.0
	for i: int in 5:
		var centre := Vector2(r + i * (star_size + 2.0), r + (size.y - star_size) / 2.0)
		var star := _star(centre, r)
		draw_colored_polygon(star, EMPTY)
		var fill := clampf(value - i, 0.0, 1.0)
		if fill >= 0.75:
			draw_colored_polygon(star, GOLD)
		elif fill >= 0.25:
			var left := PackedVector2Array([centre + Vector2(-r - 1.0, -r - 1.0), centre + Vector2(0.0, -r - 1.0),
				centre + Vector2(0.0, r + 1.0), centre + Vector2(-r - 1.0, r + 1.0)])
			for part: PackedVector2Array in Geometry2D.intersect_polygons(star, left):
				draw_colored_polygon(part, GOLD)


static func _star(centre: Vector2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k: int in 10:
		var angle := -PI / 2.0 + k * PI / 5.0
		var radius := r if k % 2 == 0 else r * 0.45
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points
