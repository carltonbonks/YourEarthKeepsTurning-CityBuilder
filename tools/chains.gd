extends SceneTree
## Writes docs/CHAINS.md (ChainChart) from the data: ~/godot/godot --headless --path . -s res://tools/chains.gd


func _init() -> void:
	var file := FileAccess.open("res://docs/CHAINS.md", FileAccess.WRITE)
	file.store_string(ChainChart.markdown(Content.load_default()))
	file.close()
	print("Wrote docs/CHAINS.md")
	quit()
