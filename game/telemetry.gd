class_name Telemetry
extends Node
## Sends anonymous play data to the playtest database, only for players who said yes (opt-in, Yusuf
## 2026-11-14): a session when the game opens, and the compact run record (RunHistory.compact) whenever
## the run is saved, so a run left half way still arrives. Nothing goes from bots, tests, desktop or
## ?dev=1 builds, local builds, or while res://telemetry.json has no address. The database side (tables
## and the two functions the public key may call) is tools/telemetry/schema.sql; docs/PRIVACY.md says
## what is sent. Presentation only: nothing here touches the run's rules.

const CONFIG := "res://telemetry.json"
## Bump when the wrapper round a record changes (the record keeps its own "format").
const UPLOAD_VERSION := 1

var settings: GameSettings
## Off for ?dev=1 and desktop builds (main.gd decides).
var dev := false
var session_id := GameSettings.new_id()
var _config := {}
var _http: HTTPRequest
var _busy := false
## The newest request waiting while one is in flight: [path, body]. Runs replace older saves of themselves.
var _waiting: Array = []
var _session_sent := false


func _ready() -> void:
	_config = load_config(CONFIG)
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.request_completed.connect(_on_done)
	add_child(_http)


## The address and public key from res://telemetry.json; {} when the file is missing.
static func load_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Whether anything may be sent: the player said yes, the database is set up, and this is the live web build.
static func allowed(config: Dictionary, share: bool, is_dev: bool, is_web: bool, host: String) -> bool:
	if not share or is_dev or not is_web:
		return false
	if str(config.get("url", "")) == "" or str(config.get("key", "")) == "":
		return false
	return host != "" and host != "localhost" and not host.begins_with("127.")


func active() -> bool:
	if settings == null:
		return false
	return allowed(_config, settings.share_data, dev, OS.has_feature("web"), _page_host())


## What a session row holds: who (the random id), which build, and the screen.
static func session_payload(player_id: String, session: String, build: String) -> Dictionary:
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i.ZERO
	return {"session_id": session, "player_id": player_id, "build": build,
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"upload_version": UPLOAD_VERSION, "screen": "%dx%d" % [screen.x, screen.y], "language": OS.get_locale_language()}


## What a run row holds: the compact record (no story) and the ids it is filed under.
static func run_payload(record: Dictionary, player_id: String, session: String) -> Dictionary:
	return {"run_id": str(record.get("id", "")), "player_id": player_id, "session_id": session,
		"upload_version": UPLOAD_VERSION, "record": RunHistory.compact(record)}


## Called when the game opens and whenever sharing is turned on.
func start_session(build: String) -> void:
	if _session_sent or not active():
		return
	_session_sent = true
	_send("rpc/log_session", {"p": session_payload(settings.player_id, session_id, build)})


## Called after every save of the run (RunHistory.save's record).
func send_run(record: Dictionary) -> void:
	if not active():
		return
	var payload := run_payload(record, settings.player_id, session_id)
	var body := JSON.stringify({"p": payload})
	if body.length() > int(_config.get("max_record_kb", 512)) * 1024:
		push_warning("Run %s is too big to send" % payload["run_id"])
		return
	_send("rpc/save_run", {"p": payload}, body)


func _send(path: String, data: Dictionary, body := "") -> void:
	if body == "":
		body = JSON.stringify(data)
	if _busy:
		# Only the newest save of a run matters; a waiting session is never replaced by a run.
		if _waiting.is_empty() or str(_waiting[0]) == path:
			_waiting = [path, body]
		return
	_busy = true
	var key := str(_config.get("key", ""))
	var headers := PackedStringArray(["Content-Type: application/json", "apikey: " + key, "Authorization: Bearer " + key])
	var url := str(_config.get("url", "")).trim_suffix("/") + "/rest/v1/" + path
	if _http.request(url, headers, HTTPClient.METHOD_POST, body) != OK:
		_busy = false


func _on_done(_result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_busy = false
	if code < 200 or code >= 300:
		push_warning("Play data not sent (HTTP %d)" % code)
	if not _waiting.is_empty():
		var next := _waiting
		_waiting = []
		_send(next[0], {}, next[1])


func _page_host() -> String:
	if not OS.has_feature("web"):
		return ""
	var host: Variant = JavaScriptBridge.eval("window.location.hostname")
	return host if host is String else ""
