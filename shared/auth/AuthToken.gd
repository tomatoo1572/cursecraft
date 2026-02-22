class_name AuthToken
extends RefCounted

const TOKEN_VERSION: int = 1

# How long a token is valid (seconds). You can tighten this later.
const DEFAULT_MAX_AGE_SEC: int = 60 * 60 * 24  # 24h

static func _hmac_sha256_hex(secret: String, message: String) -> String:
	var h := HMACContext.new()
	var err := h.start(HashingContext.HASH_SHA256, secret.to_utf8_buffer())
	if err != OK:
		return ""
	err = h.update(message.to_utf8_buffer())
	if err != OK:
		return ""
	var digest: PackedByteArray = h.finish()
	return digest.hex_encode()

static func _rand_bytes(n: int) -> PackedByteArray:
	var c := Crypto.new()
	return c.generate_random_bytes(n)

static func _nonce_b64() -> String:
	return Marshalls.raw_to_base64(_rand_bytes(16))

static func _uuid_v4() -> String:
	var b: PackedByteArray = _rand_bytes(16)
	# Set version (4) and variant (10xxxxxx)
	b[6] = (b[6] & 0x0F) | 0x40
	b[8] = (b[8] & 0x3F) | 0x80
	var hx := b.hex_encode() # 32 chars
	return "%s-%s-%s-%s-%s" % [
		hx.substr(0, 8),
		hx.substr(8, 4),
		hx.substr(12, 4),
		hx.substr(16, 4),
		hx.substr(20, 12),
	]

static func make_payload(username: String, uuid: String, secret: String) -> Dictionary:
	var issued_at := int(Time.get_unix_time_from_system())
	var nonce := _nonce_b64()

	if uuid.is_empty():
		uuid = _uuid_v4()

	var base := _base_string(username, uuid, issued_at, nonce)
	var sig := _hmac_sha256_hex(secret, base)

	return {
		"version": TOKEN_VERSION,
		"username": username,
		"uuid": uuid,
		"issued_at": issued_at,
		"nonce": nonce,
		"signature": sig,
	}

static func _base_string(username: String, uuid: String, issued_at: int, nonce: String) -> String:
	# Keep this stable. Launcher and server must match exactly.
	return "%s|%s|%d|%s" % [uuid, username, issued_at, nonce]

static func verify_payload(
	payload: Dictionary,
	secret: String,
	now_unix: int,
	max_age_sec: int = DEFAULT_MAX_AGE_SEC
) -> Dictionary:
	# Returns: { "ok": bool, "reason": String }
	if typeof(payload) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "payload_not_dict"}

	for k in ["version", "username", "uuid", "issued_at", "nonce", "signature"]:
		if not payload.has(k):
			return {"ok": false, "reason": "missing_%s" % k}

	if int(payload["version"]) != TOKEN_VERSION:
		return {"ok": false, "reason": "bad_version"}

	var username := str(payload["username"]).strip_edges()
	var uuid := str(payload["uuid"]).strip_edges()
	var issued_at := int(payload["issued_at"])
	var nonce := str(payload["nonce"]).strip_edges()
	var sig := str(payload["signature"]).strip_edges().to_lower()

	if username.is_empty() or uuid.is_empty() or nonce.is_empty() or sig.is_empty():
		return {"ok": false, "reason": "empty_fields"}

	if issued_at <= 0:
		return {"ok": false, "reason": "bad_issued_at"}

	var age := now_unix - issued_at
	if age < -120:
		return {"ok": false, "reason": "clock_skew_future"}
	if age > max_age_sec:
		return {"ok": false, "reason": "expired"}

	var base := _base_string(username, uuid, issued_at, nonce)
	var expected := _hmac_sha256_hex(secret, base).to_lower()
	if expected.is_empty():
		return {"ok": false, "reason": "hmac_error"}

	if expected != sig:
		return {"ok": false, "reason": "bad_signature"}

	return {"ok": true, "reason": ""}
