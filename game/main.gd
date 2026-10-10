extends Control
## Placeholder start screen. Proves the browser build works end to end.

@onready var _info: Label = %Info


func _ready() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version")
	var rng := SeededRng.new(4821)
	_info.text = "Version %s  ·  Godot %s\nSample seeded roll (seed %d): %d" % [
		version,
		Engine.get_version_info().string,
		rng.seed_value,
		rng.randi_range(1, 100),
	]
