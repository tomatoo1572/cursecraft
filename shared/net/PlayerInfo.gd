class_name PlayerInfo
extends RefCounted

var peer_id: int = 0
var username: String = ""
var uuid: String = ""

func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"username": username,
		"uuid": uuid,
	}

static func from_dict(d: Dictionary) -> PlayerInfo:
	var p := PlayerInfo.new()
	p.peer_id = int(d.get("peer_id", 0))
	p.username = str(d.get("username", ""))
	p.uuid = str(d.get("uuid", ""))
	return p
