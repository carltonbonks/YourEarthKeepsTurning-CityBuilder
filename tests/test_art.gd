extends TestCase
## Rendered map art (art/manifest.json, tools/render_art.sh, game/sprite_book.gd): every manifest row names a
## real content id and is rendered, every rendered sprite has its row, and walkers pick the frame for the way
## they move.

## Kinds of art and the content table their ids come from (scenery has a fixed list: things with no table of their own).
const WALKERS := ["townsfolk", "hero", "enemy"]
const SCENERY := ["barricade", "pedlar_camp", "hearth"]


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The ids a kind of art may use, or null for an unknown kind.
func _ids_for(content: Content, kind: String) -> Variant:
	match kind:
		"building":
			return content.buildings
		"townsfolk":
			return content.townsfolk
		"hero":
			return content.hero_classes
		"enemy":
			return content.enemies
		"node":
			return content.world["nodes"]
		"den":
			return content.world["dens"]
		"obstacle":
			return content.town["obstacles"]
		"plate":
			var ids := {}
			for k: String in content.plates["near_kinds"]:
				ids["plate_" + k] = true
			return ids
		"scenery":
			var ids := {}
			for k: String in SCENERY:
				ids[k] = true
			return ids
	return null


func test_manifest_rows_name_real_content_and_say_where_they_come_from() -> void:
	var content := Content.load_default()
	var rows: Dictionary = _json("res://art/manifest.json")["sprites"]
	check(not rows.is_empty(), "the manifest lists some art")
	for id: String in rows:
		var row: Dictionary = rows[id]
		var ids: Variant = _ids_for(content, str(row.get("kind", "")))
		check(ids != null, "%s has a known kind" % id)
		if ids != null:
			check((ids as Dictionary).has(id), "%s is a %s id in data/" % [id, row["kind"]])
		check(FileAccess.file_exists("res://" + str(row.get("model", ""))), "%s's model file exists" % id)
		check(str(row.get("licence", "")) != "", "%s says where it comes from (licence)" % id)
		if row.get("kind", "") in WALKERS:
			check_eq(int(row["facings"]), 8, "%s walks, so it has 8 facings" % id)
			check(float(row.get("height_r", 0.0)) > 0.0, "%s has a height_r" % id)
			check(row.get("rig", "") in ["humanoid", "quadruped", "none"], "%s has a rig the renderer can pose" % id)
		else:
			# Things that stand still: seen from one side, or 8 for those turned across the way through (gates).
			check(int(row["facings"]) in [1, 8], "%s is seen from 1 side or turned 8 ways" % id)
			check(float(row.get("world_per_unit", 0.0)) > 0.0, "%s has a world_per_unit" % id)
			check(not row.has("rig"), "%s stands still (no rig)" % id)


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
		var columns := 0
		for anim: String in info["anims"]:
			columns += int(info["anims"][anim][1])
		check_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(int(info["frame"][0]) * columns, int(info["frame"][1]) * int(info["facings"])),
			"%s's sheet holds a row per facing and a column per animation frame" % id)
		if info["kind"] in WALKERS:
			check(info["anims"].has("walk") and info["anims"].has("attack"), "%s walks and strikes" % id)
		else:
			check_eq(int(info["anims"]["idle"][1]), int(info.get("variants", 1)), "%s has a column per look" % id)
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


func test_walkers_glide_walk_strike_and_flash() -> void:
	var motion := WalkerMotion.new()
	var u := Unit.new()
	u.cooldown = 1.0
	u.hp = 10.0
	var first := motion.look(u, Vector2(100, 0), 8, 0.0)
	check_eq(int(first["facing"]), 4, "a newcomer faces the hearth")
	check(not first["walking"], "standing still at first")
	var moved := motion.look(u, Vector2(110, 0), 8, 16.0)
	check(moved["walking"], "a unit that moved walks")
	check(Vector2(moved["at"]).x > 100.0 and Vector2(moved["at"]).x < 110.0, "the drawn spot glides toward the real one")
	check_eq(int(moved["facing"]), 0, "it faces the way it moved")
	var later := motion.look(u, Vector2(110, 0), 8, 1000.0)
	check(not later["walking"], "it stands once it stops")
	check(Vector2(later["at"]).distance_to(Vector2(110, 0)) < 0.1, "and has caught up")
	u.cooldown_left = 1.0
	u.hp = 7.0
	var struck := motion.look(u, Vector2(110, 0), 8, 1016.0)
	check(float(struck["attack"]) >= 0.0, "a blow starts the swing")
	check(Color(struck["tint"]).r > 1.0, "a hit flashes")
	var after := motion.look(u, Vector2(110, 0), 8, 1016.0 + WalkerMotion.ATTACK_MS + 1.0)
	check_eq(float(after["attack"]), -1.0, "the swing plays once")
	check_eq(Color(after["tint"]), Color.WHITE, "the flash fades")
	var book := SpriteBook.new()
	check_eq(book.walker_frame("tribesperson", struck)["anim"], "attack", "a swing shows the attack frames")
	check_eq(book.walker_frame("tribesperson", moved)["anim"], "walk", "a walker shows the walk frames")
	check_eq(book.walker_frame("tribesperson", later)["anim"], "idle", "a stander stands")


func test_plates_carry_their_own_look_and_turn_with_the_ring() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var w := run.world
	var props := GroundProps.new()
	var all := func(_id: String) -> bool: return true
	var laid := props.props(w, 0.0, all)
	check(laid.size() > 40, "the plates are dressed (%d props)" % laid.size())
	var near: Dictionary = w.earth.rings[0]
	for p: Array in laid:
		var at: Vector2 = p[0]
		check(at.length() >= float(near["r0"]) and at.length() <= float(near["r1"]), "props stay on the turning ring")
		check(p[1] == "plate_" + w.earth.kind_at(at), "each prop shows its own plate's kind")
		for node in w.nodes:
			if w.node_active(node):
				check(at.distance_to(node["pos"]) >= GroundProps.KEEP_CLEAR, "props keep clear of nodes")
	check_eq(props.props(w, 0.0, all).size(), laid.size(), "the same props every frame")
	var turned := props.props(w, 0.3, all)
	if not turned.is_empty() and not laid.is_empty():
		check(Vector2(turned[0][0]).distance_to(laid[0][0]) > 1.0, "props slide with their plate")
	var none := func(_id: String) -> bool: return false
	check(props.props(w, 0.0, none).is_empty(), "no art, no props")
