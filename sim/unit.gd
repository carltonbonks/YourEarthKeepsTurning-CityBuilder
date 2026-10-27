class_name Unit
extends RefCounted
## One hero, townsperson or enemy. Heroes and townsfolk persist across rounds.

enum Team { HERO, FOLK, ENEMY }

var id: int
var team: Team
var type_id: String  ## Hero class, townsfolk role or enemy type id.
var display_name: String
var trait_id := ""

var pos := Vector2.ZERO
var max_hp := 1.0
var hp := 1.0
var attack := 1.0
var attack_range := 20.0
var cooldown := 1.0
var speed := 50.0
var cooldown_left := 0.0
var alive := true

## Who this unit is going after. For enemies, null means the hearth.
var target: Unit = null
## Short plain-language note on what the unit is doing, shown on screen.
var intent := ""

# Hero-only progress.
var level := 1
var xp := 0.0
var gold := 0  ## Shells the hero carries (named gold in older run records).
var kills := 0  ## Heroes and warriors both count kills (warriors for promotion).
var retreating := false
## 0 (exhausted) to hero_energy_max. Drains while awake, comes back while resting.
var energy := 100.0
var resting := false
## Index into World.buildings of the lodging this hero sleeps in; -1 sleeps by the hearth.
var lodging := -1
## Today's whim id (see "whims" in data/heroes.json).
var whim := "none"
## Equipped items by slot ("weapon", "armor", "charm"); each item is {base, tier, affixes}. See Loot.
var items := {}
## Round*10+day keys of the last tavern night paid for, the last carousing day
## and the last night the story told of this hero waking.
var paid_night := -1
var caroused := -1
var woke_night := -1
## Items carried to sell.
var spares: Array[Dictionary] = []
## Provisions bought at the market (recipe ids, e.g. "smoked_meat"), used up in the field.
var pack: Array[String] = []
## What a hero out in the wilds has sent for ("energy" or "heal"), "" if nothing (HeroAI._call_for_supplies).
var supply_call := ""
## The runner bringing it, or null.
var runner: Unit = null
## The night_key of the day this hero last traded at the pedlar's camp (once a day), or -1.
var pedlar_visit := -1
## Building index of the stall a hero is walking to, or -1.
var shop_stall := -1
## 0-100. Too low and the hero leaves town at dawn (see "_mood_note" in data/balance.json).
var mood := 60.0
## Where the hero slept last night: "favourite", "other", "rough" or "" (stayed up).
var slept := ""
## What pleased the hero since the last dawn: {"bought": 1, "prize": n}.
var mood_events := {}

# Walking: the cached route (see Pathing.next_point).
var path := PackedVector2Array()
var path_index := 0
var path_goal := Vector2.ZERO
var path_version := -1

# Townsfolk work.
var task := ""  ## e.g. "gather", "return", "build", "repair", "home".
var task_index := -1  ## Node or building index the task is about.
var task_timer := 0.0
var carrying := ""
var carry_amount := 0
var home := Vector2.ZERO
var joined_round := 1
## Goods finished at each workshop type, e.g. {"knapper": 5}.
var made := {}
## A runner's errand: the hero it carries supplies to (null when not running) and the stall good it carries ({} until
## fetched). See FolkAI._run_errand.
var errand_for: Unit = null
var parcel := {}
## A promoted craftsperson: the workshop type they master and their craft trait (data/promotions.json).
var master_of := ""
var craft_trait := ""
## Heroes: ate a hearty meal this dawn (earns more XP until the next dawn).
var well_fed := false
## A hero with a hound from the kennel hits harder; the hound runs off when the hero falls back badly hurt.
var hound := false
## Townsfolk: hired for this round only from the caravan (Trade path tier II); they leave as the round ends.
var hired := false
## Townsfolk: the leaning their dawn card came with (a key of their role's "leanings"), or "".
var leaning := ""
## Townsfolk: a gatherer a warrior keeps watch over walks faster while no foe is near (set each step, FolkAI).
var escorted := false
## Townsfolk: the lasting mark earned (a key of data/marks.json, or "") and the hero who taught it.
var mark := ""
var mark_from := ""
## Townsfolk: the powerful or transmuting modifiers their rolled dawn card came with (keys of data/card_mods.json).
var boons: Array[String] = []
## Warriors: the hero they drill beside (null when not drilling) and seconds drilled toward a mark so far.
var drill_with: Unit = null
var drill_seconds := 0.0
## Heroes: when they last drilled (World.time), so warriors drilling beside them know they still are.
var drilled_at := -1.0
## Townsfolk at work (FolkAI._note_time): what they did this step when their task doesn't say ("flee", "fight",
## "heal", "patrol", "shadow", "drill"; "" = their task), and seconds this round by time kind (work, fallback, idle,
## down; townsfolk.json time_kinds) with last round's kept for the Your people panel, plus goods carried home.
var activity := ""
var time := {}
var time_last := {}
var brought := 0
var brought_last := 0
## The barricade (index into World.barricades) this townsperson runs to raise, -1 for none.
var barricade := -1

# Enemy-only.
var spawn_time := 0.0
var spawned := false
var is_boss := false
var den_index := -1  ## Which den a wanderer belongs to; -1 for wave enemies.
var wander_goal := Vector2.ZERO
var is_probe := false  ## Part of a small raid on an early night.
## Seen by the town (EnemyAI.spot_tick): the alarm has been raised for it.
var spotted := false
## Sentient enemies chase whoever last hurt them until this time.
var grudge_until := -1.0
## A sentient enemy shot by a tower goes for that building (index into World.buildings), -1 for none.
var target_tower := -1
## A fallen enemy raised to fight for the town until dawn (Bone Flute): not counted as a townsperson.
var risen := false
## A raider who fell on a Barrow and got up again (it only does so once).
var rose_again := false


func is_hero() -> bool:
	return team == Team.HERO


func is_folk() -> bool:
	return team == Team.FOLK


func is_enemy() -> bool:
	return team == Team.ENEMY


func hp_fraction() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0
