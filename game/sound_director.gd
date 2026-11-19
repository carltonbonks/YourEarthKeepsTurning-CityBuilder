class_name SoundDirector
extends Node
## Plays the game's sounds by moment (the sound plan, 2026-11-19). Code asks for a key such as "card.pick", never
## a file: audio/manifest.json says which files a key has, the bus it plays on, how loud, how much its pitch wanders,
## how many may sound at once and how soon it may repeat (docs/SOUND_SPEC.md). The sim stays silent: this only
## watches the interface and, in later slices, the run.
##
## It hears the interface by itself, so no screen has to remember to: any button pressed clicks (a check box or a
## list toggles), the mouse resting on a card touches it, and cards that appear on screen are dealt with a flip
## each, then a glint for the rarest roll among them. A screen rebuilt with the same cards stays silent.
## Anything else plays with SoundDirector.cue("key").

const MANIFEST := "res://audio/manifest.json"
const AUDIO_DIR := "res://audio/"
## The mixer's buses past Master, as default_bus_layout.tres has them (made here too if the layout is missing).
const BUSES := ["Music", "Ambience", "World", "UI", "Stingers"]
## Dealt cards flip one after another, this far apart, and at most this many flips for one deal.
const DEAL_GAP_MS := 70
const DEAL_MAX := 5
## The glint for a rare card comes this long after the last flip.
const ROLL_DELAY_MS := 90
const ROLL_KEYS := {"blue": "card.roll_blue", "yellow": "card.roll_yellow", "orange": "card.roll_orange"}
const ROLL_ORDER := ["white", "blue", "yellow", "orange"]

## The director in the running game, so any part can cue a sound; null in tests, where cue() does nothing.
static var current: SoundDirector = null

## key -> its manifest row.
var sounds := {}
## Every key cued since start (tests and the debug view read it), and the last one.
var cued: Array[String] = []
var _streams := {}
var _players := {}
var _last_ms := {}
## [due msec, key] waiting to play (dealt cards' flips, one after another).
var _queue: Array = []
## Cards seen in the tree, and which were on screen last frame (by what they show), so a rebuild is silent.
var _cards: Array = []
var _showing := {}
var _rng := RandomNumberGenerator.new()


## Plays `key` on the running game's director, if there is one.
static func cue(key: String) -> void:
	if current != null:
		current.play(key)


func _init() -> void:
	_rng.randomize()
	ensure_buses()
	load_manifest()


func _enter_tree() -> void:
	current = self
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if current == self:
		current = null
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


static func read_manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return (parsed as Dictionary).get("sounds", {}) if parsed is Dictionary else {}


func load_manifest() -> void:
	sounds = read_manifest()
	_streams.clear()
	for key: String in sounds:
		var list: Array = []
		for file: String in sounds[key].get("files", []):
			var stream := load(AUDIO_DIR + file) as AudioStream
			if stream != null:
				list.append(stream)
		_streams[key] = list


## Adds any of BUSES the layout lacks, each sending to Master.
static func ensure_buses() -> void:
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")


## Plays one of `key`'s files, unless it played within its cooldown or all its voices are busy. Returns whether it did.
func play(key: String) -> bool:
	if not sounds.has(key):
		push_warning("SoundDirector: no sound for \"%s\" in audio/manifest.json" % key)
		return false
	var row: Dictionary = sounds[key]
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(key, -100000)) < int(float(row.get("cooldown_s", 0.0)) * 1000.0):
		return false
	var streams: Array = _streams.get(key, [])
	if streams.is_empty():
		return false
	var player := _free_player(key, int(row.get("max_voices", 1)))
	if player == null:
		return false
	_last_ms[key] = now
	cued.append(key)
	player.stream = streams[_rng.randi() % streams.size()]
	player.bus = str(row.get("bus", "Master"))
	player.volume_db = float(row.get("volume_db", 0.0))
	var jitter := float(row.get("pitch_jitter", 0.0))
	player.pitch_scale = 1.0 + _rng.randf_range(-jitter, jitter)
	if player.is_inside_tree():
		player.play()
	return true


## Plays `key` after `delay_ms`.
func play_later(key: String, delay_ms: int) -> void:
	_queue.append([Time.get_ticks_msec() + delay_ms, key])


func _free_player(key: String, max_voices: int) -> AudioStreamPlayer:
	var pool: Array = _players.get(key, [])
	for p: AudioStreamPlayer in pool:
		if not p.playing and not p.has_meta("_used"):
			return p
	if pool.size() >= maxi(1, max_voices):
		return null
	var p := AudioStreamPlayer.new()
	add_child(p)
	# Out of the tree (tests) a player never starts, so it counts as busy once used.
	if not is_inside_tree():
		p.set_meta("_used", true)
	pool.append(p)
	_players[key] = pool
	return p


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var due := _queue.filter(func(q: Array) -> bool: return int(q[0]) <= now)
	if not due.is_empty():
		_queue = _queue.filter(func(q: Array) -> bool: return int(q[0]) > now)
		for q: Array in due:
			play(str(q[1]))
	_watch_cards()


## Hooks every button as it enters the tree (once each).
func _on_node_added(node: Node) -> void:
	if not node is BaseButton or node.has_meta("_sound"):
		return
	node.set_meta("_sound", true)
	var button := node as BaseButton
	if button is CardView:
		_cards.append(button)
		button.pressed.connect(play.bind("card.pick"))
		button.mouse_entered.connect(func() -> void:
			if not button.disabled:
				play("ui.hover"))
	elif button is OptionButton:
		button.pressed.connect(play.bind("ui.click"))
		(button as OptionButton).item_selected.connect(func(_i: int) -> void: play("ui.toggle"))
	elif button.toggle_mode:
		button.toggled.connect(func(_on: bool) -> void: play("ui.toggle"))
	else:
		button.pressed.connect(play.bind("ui.click"))


## What a card shows, so the same card rebuilt reads as the same card.
static func card_key(card: CardView) -> String:
	return "%s|%s|%s" % [card.family, card.title_label.text if card.title_label != null else "", card.roll]


## The cards on screen this frame.
func _watch_cards() -> void:
	_cards = _cards.filter(func(c: Variant) -> bool: return is_instance_valid(c) and (c as Node).is_inside_tree())
	note_cards(_cards.filter(func(c: CardView) -> bool: return c.is_visible_in_tree() and not c.is_queued_for_deletion()))


## Given the cards on screen now, deals the ones that weren't last time: a flip each (up to DEAL_MAX), then the
## rarest roll's glint.
func note_cards(cards: Array) -> void:
	var showing := {}
	var fresh := 0
	var rarest := 0
	for card: CardView in cards:
		var k := card_key(card)
		if showing.has(k):
			continue
		showing[k] = true
		if not _showing.has(k):
			fresh += 1
			rarest = maxi(rarest, ROLL_ORDER.find(card.roll))
	_showing = showing
	deal(fresh, ROLL_ORDER[rarest] if rarest > 0 else "white")


## The sound of `count` cards dealt, the rarest of them rolled `rarest`.
func deal(count: int, rarest := "white") -> void:
	if count <= 0:
		return
	var flips := mini(count, DEAL_MAX)
	for i in flips:
		play_later("card.deal", i * DEAL_GAP_MS)
	if ROLL_KEYS.has(rarest):
		play_later(ROLL_KEYS[rarest], (flips - 1) * DEAL_GAP_MS + ROLL_DELAY_MS)
