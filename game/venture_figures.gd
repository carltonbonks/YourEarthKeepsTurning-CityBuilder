class_name VentureFigures
extends Control
## A row of little tribespeople for a venture: one figure per person sent, a bold red X over each one
## who never comes home. On a dawn card the losses aren't rolled yet, so the sure ones get a bold X and
## the ones that may or may not come back a faint one; after the venture every X is a real death.
## Drawn with lines (placeholder art), so no font needs the glyphs.

const HOME_COLOR := Color("#c9b48a")
const DEAD_BODY := Color("#5b5f66")
const X_COLOR := Color("#ff4a3a")

## Figures in the row, how many surely die, and how many more may.
var send := 0
var dead := 0
var maybe := 0
## Figure width in pixels; the height follows.
var figure := 14.0


static func make(send_count: int, dead_count: int, maybe_count := 0, figure_width := 14.0) -> VentureFigures:
	var f := VentureFigures.new()
	f.send = send_count
	f.dead = mini(dead_count, send_count)
	f.maybe = clampi(maybe_count, 0, send_count - f.dead)
	f.figure = figure_width
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.custom_minimum_size = Vector2(send_count * figure_width * 1.25, figure_width * 1.5)
	return f


func _draw() -> void:
	var step := figure * 1.25
	var x0 := (size.x - step * send) / 2.0
	for i in send:
		# The dead come first, then those at risk, then those sure to come home.
		var kind := "dead" if i < dead else ("maybe" if i < dead + maybe else "home")
		var c := Vector2(x0 + step * (i + 0.5), size.y / 2.0)
		var body := HOME_COLOR if kind == "home" else (DEAD_BODY if kind == "dead" else Color(HOME_COLOR, 0.7))
		var h := figure * 1.5
		draw_circle(c + Vector2(0, -h * 0.3), figure * 0.2, body)
		draw_rect(Rect2(c + Vector2(-figure * 0.28, -h * 0.12), Vector2(figure * 0.56, h * 0.48)), body)
		if kind == "home":
			continue
		var r := figure * 0.45
		var col := X_COLOR if kind == "dead" else Color(X_COLOR, 0.45)
		var w := maxf(2.0, figure * 0.16) if kind == "dead" else maxf(1.5, figure * 0.1)
		draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, w, true)
		draw_line(c + Vector2(r, -r), c + Vector2(-r, r), col, w, true)
