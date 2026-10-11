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
var kills := 0
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
## Building index of the stall a hero is walking to, or -1.
var shop_stall := -1

# Townsfolk work.
var task := ""  ## e.g. "gather", "return", "build", "repair", "home".
var task_index := -1  ## Node or building index the task is about.
var task_timer := 0.0
var carrying := ""
var carry_amount := 0
var home := Vector2.ZERO

# Enemy-only.
var spawn_time := 0.0
var spawned := false
var is_boss := false
var den_index := -1  ## Which den a wanderer belongs to; -1 for wave enemies.
var wander_goal := Vector2.ZERO
var is_probe := false  ## Part of a small raid on an early night.
## Sentient enemies chase whoever last hurt them until this time.
var grudge_until := -1.0


func is_hero() -> bool:
	return team == Team.HERO


func is_folk() -> bool:
	return team == Team.FOLK


func is_enemy() -> bool:
	return team == Team.ENEMY


func hp_fraction() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0
