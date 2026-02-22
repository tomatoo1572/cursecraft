extends RefCounted
class_name WorldSession

var world_id: String = ""
var meta: Dictionary = {}

var sim: WorldSim = null

func _init(world_meta: Dictionary) -> void:
	meta = world_meta.duplicate(true)
	world_id = str(meta.get("world_id", ""))

	var seed_i: int = int(meta.get("seed", 0))
	var preset: String = str(meta.get("worldgen_preset", "default"))
	var mode: String = str(meta.get("game_mode", "survival"))

	sim = WorldSim.new(world_id, seed_i, preset, mode)

func get_spawn_array() -> Array:
	var sv: Variant = meta.get("spawn", [0, 64, 0])
	if sv is Array:
		var a: Array = sv as Array
		if a.size() == 3:
			return [int(a[0]), int(a[1]), int(a[2])]
	return [0, 64, 0]
