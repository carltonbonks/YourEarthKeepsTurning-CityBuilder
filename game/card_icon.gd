class_name CardIcon
extends Control
## A small placeholder icon drawn with lines and shapes, for the cards (CardView): what kind of card it is,
## the goods on a price or a reward, the people a card brings. Swappable art: nothing reads an icon but the view.
## Goods with no shape of their own draw as a dot in their top-bar colour (StatusText.RESOURCE_COLORS).

## Goods drawn with a shape of their own; any other good is a coloured dot and the card names it.
const GOODS_SHAPES := ["wood", "stone", "shells", "food", "fuel"]

var icon := ""
var color := Color.WHITE
## A second colour some icons use (an outline, a mark).
var accent := Color(0, 0, 0, 0.6)


static func make(id: String, tint: Color, px := 14.0) -> CardIcon:
	var i := CardIcon.new()
	i.icon = id
	i.color = tint
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return i


## A good's icon: its own shape when it has one, otherwise a dot in its colour.
static func good(id: String, px := 13.0) -> CardIcon:
	var tint := Color(StatusText.RESOURCE_COLORS.get(id, "#c8ccd4"))
	return make(id if id in GOODS_SHAPES else "dot", tint, px)


static func has_shape(good_id: String) -> bool:
	return good_id in GOODS_SHAPES


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	match icon:
		"folk", "warrior":
			draw_circle(p.call(0.5, 0.24), s * 0.18, color)
			draw_colored_polygon(PackedVector2Array([p.call(0.18, 1.0), p.call(0.22, 0.58), p.call(0.5, 0.46), p.call(0.78, 0.58), p.call(0.82, 1.0)]), color)
			if icon == "warrior":
				draw_line(p.call(0.92, 0.02), p.call(0.74, 0.7), color.lightened(0.3), maxf(1.0, s * 0.09))
		"family":
			draw_circle(p.call(0.3, 0.25), s * 0.15, color)
			draw_colored_polygon(PackedVector2Array([p.call(0.06, 1.0), p.call(0.1, 0.6), p.call(0.3, 0.48), p.call(0.5, 0.6), p.call(0.54, 1.0)]), color)
			draw_circle(p.call(0.74, 0.45), s * 0.12, color)
			draw_colored_polygon(PackedVector2Array([p.call(0.56, 1.0), p.call(0.6, 0.72), p.call(0.74, 0.62), p.call(0.88, 0.72), p.call(0.92, 1.0)]), color)
		"hero", "spark":
			var pts := PackedVector2Array()
			var points := 5 if icon == "hero" else 4
			for k in points * 2:
				var a := -PI / 2.0 + k * PI / points
				var r := 0.5 if k % 2 == 0 else (0.22 if icon == "hero" else 0.14)
				pts.append(p.call(0.5 + cos(a) * r, 0.52 + sin(a) * r))
			draw_colored_polygon(pts, color)
		"up":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.05), p.call(0.95, 0.55), p.call(0.66, 0.55), p.call(0.66, 0.95),
				p.call(0.34, 0.95), p.call(0.34, 0.55), p.call(0.05, 0.55)]), color)
		"house":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.06), p.call(0.95, 0.46), p.call(0.95, 0.95), p.call(0.05, 0.95), p.call(0.05, 0.46)]), color)
		"hammer":
			draw_rect(Rect2(p.call(0.1, 0.12), Vector2(0.62, 0.3) * s), color)
			draw_rect(Rect2(p.call(0.42, 0.4), Vector2(0.18, 0.56) * s), color)
		"flag":
			draw_line(p.call(0.2, 0.04), p.call(0.2, 0.98), color, maxf(1.0, s * 0.1))
			draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.08), p.call(0.92, 0.08), p.call(0.7, 0.3), p.call(0.92, 0.52), p.call(0.2, 0.52)]), color)
		"cart":
			draw_colored_polygon(PackedVector2Array([p.call(0.05, 0.25), p.call(0.95, 0.25), p.call(0.82, 0.68), p.call(0.18, 0.68)]), color)
			draw_circle(p.call(0.3, 0.84), s * 0.12, color)
			draw_circle(p.call(0.7, 0.84), s * 0.12, color)
		"map":
			draw_colored_polygon(PackedVector2Array([p.call(0.05, 0.18), p.call(0.35, 0.06), p.call(0.65, 0.18), p.call(0.95, 0.06),
				p.call(0.95, 0.82), p.call(0.65, 0.94), p.call(0.35, 0.82), p.call(0.05, 0.94)]), color)
			draw_line(p.call(0.35, 0.06), p.call(0.35, 0.82), accent, 1.0)
			draw_line(p.call(0.65, 0.18), p.call(0.65, 0.94), accent, 1.0)
		"relic":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.04), p.call(0.92, 0.2), p.call(0.88, 0.58), p.call(0.5, 0.96),
				p.call(0.12, 0.58), p.call(0.08, 0.2)]), color)
		"sack":
			draw_colored_polygon(PackedVector2Array([p.call(0.36, 0.06), p.call(0.64, 0.06), p.call(0.58, 0.28), p.call(0.9, 0.62),
				p.call(0.8, 0.94), p.call(0.2, 0.94), p.call(0.1, 0.62), p.call(0.42, 0.28)]), color)
		"earth":
			draw_colored_polygon(PackedVector2Array([p.call(0.0, 0.92), p.call(0.3, 0.38), p.call(0.48, 0.62), p.call(0.68, 0.12), p.call(1.0, 0.92)]), color)
		"ring":
			draw_arc(p.call(0.5, 0.5), s * 0.4, 0.0, TAU, 24, color, maxf(1.5, s * 0.14))
			draw_circle(p.call(0.5, 0.5), s * 0.1, color)
		"sun":
			draw_circle(p.call(0.5, 0.56), s * 0.2, color)
			for k in 5:
				var a := PI + k * PI / 4.0
				draw_line(p.call(0.5 + cos(a) * 0.32, 0.56 + sin(a) * 0.32), p.call(0.5 + cos(a) * 0.46, 0.56 + sin(a) * 0.46), color, maxf(1.0, s * 0.08))
		"moon", "moon_empty":
			if icon == "moon":
				draw_circle(p.call(0.5, 0.5), s * 0.44, color)
			else:
				draw_arc(p.call(0.5, 0.5), s * 0.4, 0.0, TAU, 20, color, maxf(1.0, s * 0.1))
		"bed":
			draw_rect(Rect2(p.call(0.04, 0.5), Vector2(0.92, 0.26) * s), color)
			draw_rect(Rect2(p.call(0.04, 0.24), Vector2(0.14, 0.7) * s), color)
			draw_rect(Rect2(p.call(0.22, 0.34), Vector2(0.24, 0.16) * s), color)
		"diamond":
			var d := PackedVector2Array([p.call(0.5, 0.0), p.call(1.0, 0.5), p.call(0.5, 1.0), p.call(0.0, 0.5)])
			draw_colored_polygon(d, color)
			d.append(d[0])
			draw_polyline(d, accent, 1.0)
		"square":
			draw_rect(Rect2(p.call(0.15, 0.15), Vector2(0.7, 0.7) * s), color)
		"dot":
			draw_circle(p.call(0.5, 0.5), s * 0.36, color)
		"gem":
			draw_circle(p.call(0.5, 0.5), s * 0.46, Color(0, 0, 0, 0.7))
			draw_circle(p.call(0.5, 0.5), s * 0.34, color)
			draw_circle(p.call(0.4, 0.38), s * 0.1, color.lightened(0.6))
		"wood":
			draw_rect(Rect2(p.call(0.05, 0.32), Vector2(0.9, 0.38) * s), color)
			draw_circle(p.call(0.8, 0.51), s * 0.13, color.darkened(0.45))
		"stone":
			draw_colored_polygon(PackedVector2Array([p.call(0.08, 0.82), p.call(0.2, 0.36), p.call(0.55, 0.16), p.call(0.92, 0.42), p.call(0.84, 0.86)]), color)
		"shells":
			# A scallop: a half fan on a little hinge, never a gem (gems are rarity).
			var fan := PackedVector2Array([p.call(0.5, 0.84)])
			for k in 9:
				var a := PI + k * PI / 8.0
				fan.append(p.call(0.5 + cos(a) * 0.46, 0.7 + sin(a) * 0.58))
			draw_colored_polygon(fan, color)
			for k in 4:
				var a := PI + (k + 1) * PI / 5.0
				draw_line(p.call(0.5, 0.82), p.call(0.5 + cos(a) * 0.42, 0.7 + sin(a) * 0.52), color.darkened(0.45), 1.0)
			draw_rect(Rect2(p.call(0.36, 0.8), Vector2(0.28, 0.14) * s), color.darkened(0.15))
		"food":
			draw_circle(p.call(0.36, 0.62), s * 0.27, color)
			draw_circle(p.call(0.68, 0.56), s * 0.22, color.darkened(0.15))
			draw_line(p.call(0.5, 0.36), p.call(0.66, 0.06), Color("#7fbf6a"), maxf(1.0, s * 0.08))
		"fuel":
			draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.04), p.call(0.82, 0.5), p.call(0.72, 0.9), p.call(0.28, 0.9),
				p.call(0.18, 0.5), p.call(0.38, 0.36)]), color)
		"dice":
			draw_rect(Rect2(p.call(0.1, 0.1), Vector2(0.8, 0.8) * s), color, false, maxf(1.0, s * 0.08))
			for c: Vector2 in [Vector2(0.32, 0.32), Vector2(0.5, 0.5), Vector2(0.68, 0.68)]:
				draw_circle(p.call(c.x, c.y), s * 0.07, color)
		_:
			draw_circle(p.call(0.5, 0.5), s * 0.3, color)
