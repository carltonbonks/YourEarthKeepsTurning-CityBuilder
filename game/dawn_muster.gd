class_name DawnMuster
extends RefCounted
## The dawn pick as a scene in the town (Yusuf, 2026-11-05; plan https://claude.ai/artifact/Lmuz7GAThDGnWYA1JjEc3p,
## slice 1). The camera glides in on the hearth and the town's people gather behind it, one group per dawn card,
## and each group holds up its card on a pole: a role's band as it stands now with its newcomer raising the banner
## (so a fifth forager reads as one), a hero alone in their ring, a family, the townsperson to be promoted, a
## venture's party packed for the trip (a red X over each who won't come back) or a band to charter as a guild.
## The cards themselves are Overlays' CardViews laid out in a row by `layout`; the groups stand under them.
## Picking one: that group cheers, everyone goes back to what they were doing and the camera eases back.
## View only, like Victory: real townsfolk are drawn at their places (`place`), newcomers and offered heroes are
## stand-ins drawn here, and the sim never moves anyone. Timings are in real milliseconds.

## How long the camera takes to glide in, people to gather, and everyone to go back once a card is taken.
const GLIDE_MS := 900.0
const GATHER_MS := 900.0
const LEAVE_MS := 700.0
## How close the camera comes (ArenaView zoom), unless the view can't go that far.
const ZOOM := 4.0
## The most figures a group shows; the rest of a band is counted beside it ("+5 more").
const MAX_FIGURES := 10
## The screen's plan, in pixels of the map: the gap between cards and at the map's sides, the smallest a card may
## shrink to before the scene gives way to the classic pop-up, and the room under the cards for the pole, the
## figures, the rows in front, the hearth and the skip button.
const GAP := 14.0
const EDGE := 16.0
const MIN_SCALE := 0.6
const POLE := 34.0
const FIGURE := 46.0
const ROWS := 28.0
const HEARTH := 56.0
const FOOTER := 52.0
## Space between figures in a group's rows, and the rows' depth, in pixels.
const SPACING := 20.0
const ROW_DEPTH := 12.0
const PER_ROW := 4
## How much the map dims behind the groups while the scene is up, so they stand out.
const WASH := 0.4
const POLE_COLOR := Color("#5a4028")
const X_COLOR := Color("#ff4a3a")
const PACK_COLOR := Color("#6b4f33")
const TOOL_COLOR := Color("#b9a27a")

## When the scene began (ms), or -1 when there is none.
var born := -1.0
## When a card was taken (ms), or -1 while the player chooses.
var ended := -1.0
## The group whose card was taken, or -1 (none: "Nobody today").
var chosen := -1
## The groups, in the cards' order (see `gather`), each with its screen slot and figures placed.
var groups: Array = []
## Real people in the scene: unit instance id -> {spot, group, index (in the group: 0 holds the banner)}.
var _spots := {}
## Newcomers and offered heroes: {id, spot, hero, color, group, bearer}.
var stand_ins: Array = []
var _from_zoom := 1.0
var _from_pan := Vector2.ZERO
var _to_zoom := 1.0
var _to_pan := Vector2.ZERO


func active() -> bool:
	return born >= 0.0


## True while the player is choosing (the scene is up and no card has been taken).
func choosing() -> bool:
	return active() and ended < 0.0


## Who stands in each card's group, in pick_offer order: {kind, id (who holds the banner), members (real units),
## stand_ins ({id, hero, color}), kit ("", "venture" or "guild"), lose ([sure, at most] for a venture), more (people
## of the band not shown)}. A townsperson is in one group at most.
static func gather(run: RunState) -> Array:
	var taken := {}
	var out: Array = []
	for card: Dictionary in run.pick_offer:
		out.append(_group(run, card, taken))
	return out


static func _group(run: RunState, card: Dictionary, taken: Dictionary) -> Dictionary:
	var content := run.content
	var g := {"kind": card["kind"], "id": "", "members": [], "stand_ins": [], "kit": "", "lose": [0, 0], "more": 0}
	var members: Array = []
	match card["kind"]:
		"hero":
			var hero: Unit = card["hero"]
			g["id"] = hero.type_id
			g["stand_ins"] = [{"id": hero.type_id, "hero": true, "color": Color(content.hero_classes[hero.type_id]["color"])}]
		"family":
			var roles: Array = card["roles"].duplicate()
			for i in CardRoll.extra_people(content, card):
				roles.append("tribesperson")
			g["id"] = roles[0]
			for role: String in roles:
				g["stand_ins"].append(_folk_stand_in(content, role))
		"promote":
			var who: Unit = card["unit"] if card.has("unit") else card["hero"]
			g["id"] = who.type_id
			members = [who]
		"venture":
			var terms := run.people.venture_terms(card["venture"], card)
			g["kit"] = "venture"
			g["lose"] = terms["lose"]
			g["id"] = "tribesperson"
			members = _band(run, "tribesperson", "", taken, int(terms["send"]))
			for i in int(terms["send"]) - members.size():
				g["stand_ins"].append(_folk_stand_in(content, "tribesperson"))
		"guild":
			g["kit"] = "guild"
			g["id"] = "tribesperson"
			members = _band(run, "tribesperson", card["leaning"], taken, MAX_FIGURES)
			g["more"] = _band_size(run, "tribesperson", card["leaning"]) - members.size()
		_:
			var role: String = card["role"]
			var leaning: String = card.get("leaning", "")
			g["id"] = role
			for i in 1 + CardRoll.extra_people(content, card):
				g["stand_ins"].append(_folk_stand_in(content, role))
			var room := maxi(0, MAX_FIGURES - g["stand_ins"].size())
			members = _band(run, role, leaning, taken, room)
			g["more"] = _band_size(run, role, leaning) - members.size()
	for u: Unit in members:
		taken[u.get_instance_id()] = true
	g["members"] = members
	return g


static func _folk_stand_in(content: Content, role: String) -> Dictionary:
	return {"id": role, "hero": false, "color": Color(content.townsfolk[role]["color"])}


## Up to `most` of the town's living `role` townsfolk (sharing `leaning` when one is given) not already in a group.
static func _band(run: RunState, role: String, leaning: String, taken: Dictionary, most: int) -> Array:
	var out: Array = []
	for u: Unit in run.world.folk:
		if out.size() >= most:
			break
		if u.alive and u.type_id == role and (leaning == "" or u.leaning == leaning) and not taken.has(u.get_instance_id()):
			out.append(u)
	return out


static func _band_size(run: RunState, role: String, leaning: String) -> int:
	return run.world.folk.filter(func(u: Unit) -> bool:
		return u.alive and u.type_id == role and (leaning == "" or u.leaning == leaning)).size()


## Where `n` cards of size `card` and their groups go on a map of size `area`, under a header `header` pixels tall:
## {scale (of the cards), xs (each card's middle), card_top, card_bottom, feet_y (where the banner holders stand),
## hearth_y}, or {} when the cards would have to shrink below MIN_SCALE (the classic pop-up shows instead).
static func layout(n: int, card: Vector2, area: Vector2, header: float) -> Dictionary:
	if n <= 0 or area.x <= 0.0 or area.y <= 0.0:
		return {}
	var wide := (area.x - 2.0 * EDGE - (n - 1) * GAP) / (n * card.x)
	var tall := (area.y - header - POLE - FIGURE - ROWS - HEARTH - FOOTER) / card.y
	var s := minf(1.0, minf(wide, tall))
	if s < MIN_SCALE:
		return {}
	var step := card.x * s + GAP
	var xs: Array[float] = []
	for i in n:
		xs.append(area.x / 2.0 + (i - (n - 1) / 2.0) * step)
	var top := header
	var bottom := top + card.y * s
	var feet := bottom + POLE + FIGURE
	return {"scale": s, "xs": xs, "card_top": top, "card_bottom": bottom, "feet_y": feet,
		"hearth_y": feet + ROWS + HEARTH * 0.6, "card": card * s}


## Where the k-th of a group's figures stands, in pixels from where its banner holder stands: the holder at the back
## in the middle (so the pole rises clear), the rest in rows of PER_ROW in front, as wide as `room` allows.
static func formation(k: int, others: int, room: float) -> Vector2:
	if k == 0:
		return Vector2.ZERO
	var i := k - 1
	var row := i / PER_ROW
	var in_row := mini(PER_ROW, others - row * PER_ROW)
	var gap := minf(SPACING, room / maxf(1.0, in_row))
	return Vector2((i % PER_ROW - (in_row - 1) / 2.0) * gap, ROW_DEPTH * (row + 1))


## Begins the scene: the camera's way in, and a place for everyone in each card's group under that card's slot.
func start(run: RunState, view: ArenaView, plan: Dictionary, now_ms: float) -> void:
	# A second pick the same dawn (Twin fires) starts again from where the first scene's camera came from.
	if not active():
		_from_zoom = view.zoom
		_from_pan = view.pan
	born = now_ms
	ended = -1.0
	chosen = -1
	_to_zoom = minf(ZOOM, ArenaView.MAX_ZOOM)
	_to_pan = -view.world_under(Vector2(view.size.x / 2.0, plan["hearth_y"]), _to_zoom, Vector2.ZERO)
	groups = gather(run)
	_spots.clear()
	stand_ins.clear()
	var xs: Array = plan["xs"]
	var room: float = Vector2(plan["card"]).x * 0.9
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var foot := Vector2(xs[gi], plan["feet_y"])
		g["foot"] = foot
		g["banner"] = Vector2(xs[gi], plan["card_bottom"])
		var figures: int = g["stand_ins"].size() + g["members"].size()
		var k := 0
		# A newcomer holds the banner of a townsfolk card (the band stands with them); a venture's or guild's own
		# people, or the one to be promoted, hold theirs.
		for st: Dictionary in g["stand_ins"]:
			var spot := view.world_under(foot + formation(k, figures - 1, room), _to_zoom, _to_pan)
			stand_ins.append({"id": st["id"], "hero": st["hero"], "color": st["color"], "group": gi, "bearer": k == 0, "spot": spot})
			k += 1
		for u: Unit in g["members"]:
			var spot := view.world_under(foot + formation(k, figures - 1, room), _to_zoom, _to_pan)
			_spots[u.get_instance_id()] = {"spot": spot, "group": gi, "index": k}
			k += 1


## A card was taken (`index`, or -1 for nobody): that group cheers and everyone goes back.
func finish(index: int, now_ms: float) -> void:
	if not choosing():
		return
	chosen = index
	ended = now_ms


## Skips the camera's glide (Space): the scene is there at once.
func skip(now_ms: float) -> void:
	if choosing():
		born = minf(born, now_ms - maxf(GLIDE_MS, GATHER_MS))


## Moves the camera for this frame, and ends the scene once everyone has gone back.
func update(view: ArenaView, now_ms: float) -> void:
	if not active():
		return
	if ended >= 0.0:
		var k := smoothstep(0.0, LEAVE_MS, now_ms - ended)
		view.zoom = lerpf(_to_zoom, _from_zoom, k)
		view.pan = _to_pan.lerp(_from_pan, k)
		if now_ms - ended >= LEAVE_MS:
			born = -1.0
			groups.clear()
			stand_ins.clear()
			_spots.clear()
		return
	var g := smoothstep(0.0, GLIDE_MS, now_ms - born)
	view.zoom = lerpf(_from_zoom, _to_zoom, g)
	view.pan = _from_pan.lerp(_to_pan, g)


## How far everyone is toward their places: 0 before, 1 there, falling back to 0 as they go back.
func _there(now_ms: float) -> float:
	if not active():
		return 0.0
	var k := smoothstep(0.0, GATHER_MS, now_ms - born)
	if ended >= 0.0:
		k *= 1.0 - smoothstep(0.0, LEAVE_MS, now_ms - ended)
	return k


## How settled the camera is (1 once it has glided in, falling as it leaves): the poles and marks show with it.
func shown(now_ms: float) -> float:
	if not active():
		return 0.0
	var k := smoothstep(GLIDE_MS * 0.6, GLIDE_MS, now_ms - born)
	if ended >= 0.0:
		k *= 1.0 - smoothstep(0.0, LEAVE_MS * 0.5, now_ms - ended)
	return k


func has(u: Unit) -> bool:
	return active() and _spots.has(u.get_instance_id())


## Where a townsperson (or a hero to be knighted) is drawn: walking to their place in their group, standing there,
## and walking back to where they really are once a card is taken.
func place(u: Unit, now_ms: float) -> Vector2:
	if not has(u):
		return u.pos
	return u.pos.lerp(_spots[u.get_instance_id()]["spot"], _there(now_ms))


## Sets how someone in the scene looks this frame: facing the viewer once there, the banner holder holding it up,
## and the chosen group cheering.
func pose(u: Unit, look: Dictionary, now_ms: float) -> void:
	if not has(u) or _there(now_ms) < 0.95:
		return
	var s: Dictionary = _spots[u.get_instance_id()]
	look["facing"] = 1
	look["walking"] = false
	if ended >= 0.0:
		if int(s["group"]) == chosen:
			look["cheer"] = int((now_ms - ended) / 200.0 + int(s["index"])) % 2
	elif int(s["index"]) == 0:
		look["raise"] = true


## How see-through a stand-in is: fading in as the camera glides, out once a card is taken.
func stand_in_alpha(now_ms: float) -> float:
	if not active():
		return 0.0
	var k := smoothstep(0.0, GATHER_MS, now_ms - born)
	if ended >= 0.0:
		k *= 1.0 - smoothstep(0.0, LEAVE_MS, now_ms - ended)
	return k


## The animation a stand-in shows: holding the banner up, cheering when its card was taken, else standing.
func stand_in_anim(st: Dictionary, now_ms: float) -> Array:
	if ended >= 0.0:
		if int(st["group"]) == chosen:
			return ["cheer", int((now_ms - ended) / 200.0) % 2]
		return ["idle", 0]
	return ["raise", 0] if st["bearer"] else ["idle", 0]


## Screen spots this frame of each group's figures, in formation order ({at: feet on screen, height: figure px}),
## worked out by `figure` (ArenaView knows sizes): used for the poles, packs, tools and marks.
func draw(view: ArenaView, now_ms: float, figure: Callable) -> void:
	var a := shown(now_ms)
	if a <= 0.0:
		return
	var font := view.get_theme_default_font()
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var feet: Array = []
		for st: Dictionary in stand_ins:
			if int(st["group"]) == gi:
				feet.append(figure.call(st["id"], st["hero"], st["spot"]))
		for u: Unit in g["members"]:
			if u.alive:
				feet.append(figure.call(u.type_id, u.is_hero(), place(u, now_ms)))
		if feet.is_empty():
			continue
		_draw_kit(view, g, feet, a)
		# The pole: from the holder's raised hand up to the card's foot.
		var holder: Dictionary = feet[0]
		var hand: Vector2 = holder["at"] - Vector2(-holder["height"] * 0.08, holder["height"] * 0.95)
		var banner: Vector2 = g["banner"]
		if ended < 0.0 or gi == chosen:
			view.draw_line(Vector2(hand.x, banner.y), hand + Vector2(0.0, 6.0), Color(POLE_COLOR, a), 3.0)
			view.draw_line(banner + Vector2(-10.0, 0.0), banner + Vector2(10.0, 0.0), Color(POLE_COLOR, a), 3.0)
		if int(g["more"]) > 0:
			var last: Dictionary = feet[feet.size() - 1]
			var at: Vector2 = Vector2(maxf(last["at"].x, holder["at"].x) + 16.0, holder["at"].y + 4.0)
			view.draw_string_outline(font, at, "+%d more" % g["more"], HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.CAPTION, 3,
				Color(0, 0, 0, 0.7 * a))
			view.draw_string(font, at, "+%d more" % g["more"], HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.CAPTION, Color(0.95, 0.9, 0.8, a))


## A venture's party carries packs and spears, with a bold red X over each sure loss and a faint one over each
## maybe (the front rows first, so the banner holder is the last marked); a guild's band holds its tools.
func _draw_kit(view: ArenaView, g: Dictionary, feet: Array, a: float) -> void:
	if g["kit"] == "":
		return
	var n := feet.size()
	for i in n:
		var f: Dictionary = feet[i]
		var at: Vector2 = f["at"]
		var h: float = f["height"]
		if g["kit"] == "venture":
			# A rolled hide pack over the shoulder, sticking out to the left.
			view.draw_rect(Rect2(at + Vector2(-h * 0.34, -h * 0.86), Vector2(h * 0.26, h * 0.13)), Color(PACK_COLOR, a))
			if i > 0:
				view.draw_line(at + Vector2(h * 0.2, 0.0), at + Vector2(h * 0.32, -h * 1.15), Color(TOOL_COLOR, a), 1.5)
			var from_back := n - 1 - i
			var lose: Array = g["lose"]
			if from_back < int(lose[1]):
				var bold := from_back < int(lose[0])
				var over := at - Vector2(0.0, h + 7.0)
				var d := 4.0
				var c := Color(X_COLOR, a * (1.0 if bold else 0.4))
				view.draw_line(over + Vector2(-d, -d), over + Vector2(d, d), c, 2.5 if bold else 1.5)
				view.draw_line(over + Vector2(-d, d), over + Vector2(d, -d), c, 2.5 if bold else 1.5)
		elif i > 0:
			view.draw_line(at + Vector2(h * 0.18, -h * 0.2), at + Vector2(h * 0.36, -h * 0.85), Color(TOOL_COLOR, a), 2.0)
			view.draw_circle(at + Vector2(h * 0.36, -h * 0.85), 2.5, Color(TOOL_COLOR, a))
