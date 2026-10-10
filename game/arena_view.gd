class_name ArenaView
extends Control
## Draws the battlefield with placeholder shapes. Read-only: it only looks at
## the RunState / Battle and never changes them, so art can be swapped freely.

const HERO_RADIUS := 13.0
const ENEMY_RADIUS := 10.0
const BOSS_RADIUS := 20.0
const BOUNTY_COLOR := Color("#ffd24a")

var run: RunState
var battle: Battle


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if run == null:
		return
	var content := run.content
	var arena := Vector2(content.num("arena_width"), content.num("arena_height"))
	var scale_f := minf(size.x / arena.x, size.y / arena.y)
	var origin := (size - arena * scale_f) / 2.0
	var to_screen := func(p: Vector2) -> Vector2: return origin + p * scale_f
	var font := get_theme_default_font()

	draw_rect(Rect2(origin, arena * scale_f), Color("#2b3a2a"))
	# Spawn edge.
	draw_rect(Rect2(to_screen.call(Vector2(arena.x - 20, 0)), Vector2(20, arena.y) * scale_f), Color("#3a2a2a"))

	# Keep.
	var keep_pos := Vector2(80, arena.y / 2.0)
	var keep_hp := battle.keep_hp if battle != null else run.keep_hp
	var kp: Vector2 = to_screen.call(keep_pos)
	var ks := 34.0 * scale_f
	draw_rect(Rect2(kp - Vector2(ks, ks) / 2.0, Vector2(ks, ks)), Color("#8a8f99"))
	draw_rect(Rect2(kp - Vector2(ks, ks) / 2.0, Vector2(ks, ks)), Color("#c9ced8"), false, 2.0)
	_bar(kp + Vector2(-ks / 2.0, -ks / 2.0 - 10), ks, keep_hp / run.keep_max_hp(), Color("#7fd0ff"))
	draw_string(font, kp + Vector2(-ks / 2.0, ks / 2.0 + 14), "Keep", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c9ced8"))

	if battle == null:
		_draw_idle_heroes(to_screen, keep_pos, scale_f, font)
		return

	for shot in battle.shots:
		var from: Vector2 = to_screen.call(shot["from"])
		var to: Vector2 = to_screen.call(shot["to"])
		var c := Color("#fff3b0") if shot["ranged"] else Color("#ffffff")
		draw_line(from, to, Color(c, 0.6), 1.5 if shot["ranged"] else 3.0)

	for enemy in battle.enemies:
		if not enemy.alive or not enemy.spawned:
			continue
		var p: Vector2 = to_screen.call(enemy.pos)
		var r := (BOSS_RADIUS if enemy.is_boss else ENEMY_RADIUS) * scale_f
		draw_circle(p, r, Color(content.enemies[enemy.type_id]["color"]))
		_bar(p + Vector2(-r, -r - 6), r * 2.0, enemy.hp_fraction(), Color("#e05050"))
		if int(battle.bounties.get(enemy.type_id, 0)) > 0:
			draw_string(font, p + Vector2(-4, 5), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, BOUNTY_COLOR)

	for hero in battle.heroes:
		if hero.alive:
			_draw_hero(hero, to_screen.call(hero.pos), scale_f, font, true)


func _draw_idle_heroes(to_screen: Callable, keep_pos: Vector2, scale_f: float, font: Font) -> void:
	for i in run.heroes.size():
		var hero := run.heroes[i]
		var pos := keep_pos + Vector2(55, (i - (run.heroes.size() - 1) / 2.0) * 34)
		_draw_hero(hero, to_screen.call(pos), scale_f, font, false)


func _draw_hero(hero: Unit, p: Vector2, scale_f: float, font: Font, show_intent: bool) -> void:
	var r := HERO_RADIUS * maxf(scale_f, 0.8)
	var color := Color(run.content.hero_classes[hero.type_id]["color"])
	draw_circle(p, r, color)
	draw_arc(p, r, 0, TAU, 24, Color.WHITE, 1.5)
	draw_string(font, p + Vector2(-4, 5), hero.display_name.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
	_bar(p + Vector2(-r, -r - 6), r * 2.0, hero.hp_fraction(), Color("#5ee07a"))
	draw_string(font, p + Vector2(r + 4, -2), hero.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	if show_intent and hero.intent != "":
		draw_string(font, p + Vector2(r + 4, 11), hero.intent, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#c8d0c0"))


func _bar(at: Vector2, width: float, fraction: float, color: Color) -> void:
	draw_rect(Rect2(at, Vector2(width, 4)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at, Vector2(width * clampf(fraction, 0.0, 1.0), 4)), color)
