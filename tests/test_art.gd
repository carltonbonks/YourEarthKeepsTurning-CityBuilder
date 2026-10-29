extends TestCase
## Rendered map art (art/manifest.json, tools/render_art.sh, game/sprite_book.gd): every manifest row names a
## real content id and is rendered, every rendered sprite has its row, and walkers pick the frame for the way
## they move.

const KIND_TABLES := {"building": "buildings", "townsfolk": "townsfolk", "hero": "hero_classes", "enemy": "enemies"}


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_manifest_rows_name_real_content_and_say_where_they_come_from() -> void:
	var content := Content.load_default()
	var rows: Dictionary = _json("res://art/manifest.json")["sprites"]
	check(not rows.is_empty(), "the manifest lists some art")
	for id: String in rows:
		var row: Dictionary = rows[id]
		check(KIND_TABLES.has(row.get("kind", "")), "%s has a known kind" % id)
		if KIND_TABLES.has(row.get("kind", "")):
			var table: Dictionary = content.get(KIND_TABLES[row["kind"]])
			check(table.has(id), "%s is a %s id in data/" % [id, row["kind"]])
		check(FileAccess.file_exists("res://" + str(row.get("model", ""))), "%s's model file exists" % id)
		check(str(row.get("licence", "")) != "", "%s says where it comes from (licence)" % id)
		if row.get("kind", "") == "building":
			check_eq(int(row["facings"]), 1, "%s is a building, seen from one side" % id)
			check(float(row.get("world_per_unit", 0.0)) > 0.0, "%s has a world_per_unit" % id)
		else:
			check_eq(int(row["facings"]), 8, "%s walks, so it has 8 facings" % id)
			check(float(row.get("height_r", 0.0)) > 0.0, "%s has a height_r" % id)


func test_every_row_is_rendered_and_every_sprite_has_a_row() -> void:
	var rows: Dictionary = _json("res://art/manifest.json")["sprites"]
	var rendered: Dictionary = _json("res://art/sprites/index.json")["sprites"]
	for id: String in rows:
		check(rendered.has(id), "%s is rendered (run tools/render_art.sh %s)" % [id, id])
	for id: String in rendered:
		check(rows.has(id), "%s in art/sprites has a manifest row" % id)
	var book := SpriteBook.new()
	for id: String in rendered:
		check(book.has(id), "the game loads %s's sprite" % id)
		if not book.has(id):
			continue
		var info := book.info(id)
		var tex: Texture2D = info["texture"]
		check_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(int(info["frame"][0]) * int(info["facings"]), int(info["frame"][1])),
			"%s's sheet holds one frame per facing" % id)
		check(float(info["figure_px"]) > 0.0, "%s stands above its feet" % id)


func test_walkers_face_the_way_they_move() -> void:
	check_eq(SpriteBook.facing_of(Vector2(1, 0), 8), 0, "along +x is facing 0")
	check_eq(SpriteBook.facing_of(Vector2(1, 1), 8), 1, "facings turn toward +y")
	check_eq(SpriteBook.facing_of(Vector2(0, 1), 8), 2, "+y is a quarter turn")
	check_eq(SpriteBook.facing_of(Vector2(-1, 0), 8), 4, "-x is half a turn")
	check_eq(SpriteBook.facing_of(Vector2(0.2, -1), 8), 6, "nearly -y rounds to facing 6")
	check_eq(SpriteBook.facing_of(Vector2(1, -0.1), 8), 0, "just short of a full turn is facing 0")
	check_eq(SpriteBook.facing_of(Vector2(0, 1), 1), 0, "a building has one facing")


func test_sprites_draw_only_tilted_and_with_the_setting_on() -> void:
	var view := ArenaView.new()
	check(view.sprites.has("hut"), "the hut has art")
	check(view._has_art("hut"), "tilted with Rendered art on, the hut is its sprite")
	check(not view._has_art("longhouse_never_drawn"), "an id with no art keeps its shape")
	view.art = false
	check(not view._has_art("hut"), "Rendered art off draws shapes")
	view.art = true
	view.iso = false
	check(not view._has_art("hut"), "the flat map is always shapes")
	view.free()
