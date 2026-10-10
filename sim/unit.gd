class_name Unit
extends RefCounted
## One hero or enemy. Heroes persist across rounds; enemies live for one wave.

enum Team { HERO, ENEMY }

var id: int
var team: Team
var type_id: String  ## Hero class id or enemy type id.
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

## Who this unit is going after. For enemies, null means the keep.
var target: Unit = null
## Short plain-language note on what the unit is doing, shown on screen.
var intent := ""

# Hero-only progress.
var level := 1
var xp := 0.0
var gold := 0
var weapon_tier := 0
var armor_tier := 0
var kills := 0
var retreating := false

# Enemy-only.
var spawn_time := 0.0
var spawned := false
var is_boss := false


func is_hero() -> bool:
	return team == Team.HERO


func hp_fraction() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0
