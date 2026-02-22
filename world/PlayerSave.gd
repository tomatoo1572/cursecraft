extends RefCounted
class_name PlayerSave

const DEFAULT_MAX_STACK: int = 64
const DEFAULT_INV_SIZE: int = 36

var player_id: String = "local"
var display_name: String = "Player"

var pos: Vector3i = Vector3i(0, 64, 0)
var yaw: float = 0.0
var pitch: float = 0.0

var health: int = 20
var hunger: int = 20

# Array of stacks: {"item_id": String, "count": int}
var inventory: Array[Dictionary] = []

var created_utc: String = ""
var last_saved_utc: String = ""

func _init() -> void:
	inventory = []
	ensure_inventory_size(DEFAULT_INV_SIZE)

func ensure_inventory_size(size: int) -> void:
	if size <= 0:
		return
	while inventory.size() < size:
		inventory.append({"item_id": "core:air", "count": 0})
	while inventory.size() > size:
		inventory.pop_back()

func to_dict(world_id: String) -> Dictionary:
	return {
		"world_id": world_id,
		"player_id": player_id,
		"display_name": display_name,
		"pos": [pos.x, pos.y, pos.z],
		"yaw": yaw,
		"pitch": pitch,
		"health": health,
		"hunger": hunger,
		"inventory": inventory.duplicate(true),
		"created_utc": created_utc,
		"last_saved_utc": last_saved_utc
	}

static func from_dict(d: Dictionary) -> PlayerSave:
	var p: PlayerSave = PlayerSave.new()

	p.player_id = str(d.get("player_id", "local"))
	if p.player_id.strip_edges().is_empty():
		p.player_id = "local"

	p.display_name = str(d.get("display_name", "Player"))
	if p.display_name.strip_edges().is_empty():
		p.display_name = "Player"

	var pv: Variant = d.get("pos", [0, 64, 0])
	if pv is Array:
		var a: Array = pv as Array
		if a.size() == 3:
			p.pos = Vector3i(int(a[0]), int(a[1]), int(a[2]))

	p.yaw = float(d.get("yaw", 0.0))
	p.pitch = float(d.get("pitch", 0.0))

	p.health = int(d.get("health", 20))
	p.hunger = int(d.get("hunger", 20))

	p.created_utc = str(d.get("created_utc", ""))
	p.last_saved_utc = str(d.get("last_saved_utc", ""))

	var inv_v: Variant = d.get("inventory", [])
	p.inventory = []
	if inv_v is Array:
		var inv_arr: Array = inv_v as Array
		for e in inv_arr:
			if e is Dictionary:
				var ed: Dictionary = e as Dictionary
				var iid: String = str(ed.get("item_id", "core:air"))
				var cnt: int = int(ed.get("count", 0))
				p.inventory.append({"item_id": iid, "count": cnt})

	p.ensure_inventory_size(DEFAULT_INV_SIZE)
	p._sanitize_inventory()

	return p

func _sanitize_inventory() -> void:
	for i in inventory.size():
		var s: Dictionary = inventory[i]
		var iid: String = str(s.get("item_id", "core:air"))
		var cnt: int = int(s.get("count", 0))

		if iid.strip_edges().is_empty():
			iid = "core:air"
		if cnt < 0:
			cnt = 0

		var max_stack: int = _get_max_stack(iid)
		if cnt > max_stack:
			cnt = max_stack

		inventory[i] = {"item_id": iid, "count": cnt}

func add_item(item_id: String, amount: int) -> int:
	# Returns how many were actually added.
	if amount <= 0:
		return 0

	var iid: String = item_id.strip_edges()
	if iid.is_empty():
		return 0

	if ContentRegistry != null and ContentRegistry.has_method("has_item"):
		if not bool(ContentRegistry.call("has_item", iid)):
			return 0

	var max_stack: int = _get_max_stack(iid)
	var remaining: int = amount

	# First fill existing stacks
	for i in inventory.size():
		if remaining <= 0:
			break
		var s: Dictionary = inventory[i]
		var sid: String = str(s.get("item_id", "core:air"))
		var cnt: int = int(s.get("count", 0))
		if sid == iid and cnt > 0 and cnt < max_stack:
			var can_add: int = max_stack - cnt
			var add_now: int = min(can_add, remaining)
			cnt += add_now
			remaining -= add_now
			inventory[i] = {"item_id": sid, "count": cnt}

	# Then use empty slots
	for j in inventory.size():
		if remaining <= 0:
			break
		var s2: Dictionary = inventory[j]
		var sid2: String = str(s2.get("item_id", "core:air"))
		var cnt2: int = int(s2.get("count", 0))
		if sid2 == "core:air" or cnt2 == 0:
			var add2: int = min(max_stack, remaining)
			remaining -= add2
			inventory[j] = {"item_id": iid, "count": add2}

	return amount - remaining

func _get_max_stack(item_id: String) -> int:
	if ContentRegistry != null and ContentRegistry.has_method("get_item"):
		var it: ItemDef = ContentRegistry.call("get_item", item_id) as ItemDef
		if it != null and it.max_stack > 0:
			return it.max_stack
	return DEFAULT_MAX_STACK
