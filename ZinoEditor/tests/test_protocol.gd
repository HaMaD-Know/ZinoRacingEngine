extends ZinoTest

func test_whitelist_and_payload_validation() -> void:
	var cube := ZinoEntities.primitive("cube")
	check_eq(ZinoProtocol.validate_request("PING", {}), "", "PING ok")
	check(ZinoProtocol.validate_request("RUN_SHELL", {}) != "", "unknown command rejected")
	check(ZinoProtocol.validate_request(42, {}) != "", "non-string command rejected")
	check(ZinoProtocol.validate_request("PING", []) != "", "non-object payload rejected")
	check_eq(ZinoProtocol.validate_request("CREATE_OBJECT", {"entity": cube}), "", "valid entity ok")
	var bad := cube.duplicate(true)
	bad["id"] = "../../etc"
	check(ZinoProtocol.validate_request("CREATE_OBJECT", {"entity": bad}) != "", "bad id rejected")
	check(ZinoProtocol.validate_request("MOVE_OBJECT", {"id": cube["id"], "position": [0, NAN, 0]}) != "", "NaN rejected")
	check_eq(ZinoProtocol.validate_request("MOVE_OBJECT", {"id": cube["id"], "position": [1, 2, 3]}), "", "move ok")
	check(ZinoProtocol.validate_request("DELETE_OBJECT", {"ids": []}) != "", "empty delete rejected")
	check_eq(ZinoProtocol.validate_request("SELECT_OBJECT", {"ids": []}), "", "empty selection allowed (clears it)")
	check(ZinoProtocol.validate_request("LOAD_SCENE", {"scene": {"format": "nope"}}) != "", "bad scene rejected")
	check_eq(ZinoProtocol.validate_request("LOAD_SCENE", {"scene": ZinoTemplates.racing_test_scene(), "sceneName": "Main"}), "", "valid scene ok")
	check(ZinoProtocol.validate_request("SAVE_SCENE", {"sceneName": "../evil"}) != "", "path traversal in scene name rejected")

func test_import_paths_are_confined_to_assets() -> void:
	check_eq(ZinoProtocol.validate_request("IMPORT_ASSET", {"path": "Assets/Vehicles/car.glb"}), "", "asset path ok")
	for p in ["C:/Windows/system32/x.dll", "/etc/passwd", "Assets/../project.godot", "addons/x.gd", "", "res://x"]:
		check(ZinoProtocol.validate_request("IMPORT_ASSET", {"path": p}) != "", "rejected: " + p)

func test_token_compare() -> void:
	var t := ZinoProtocol.new_token()
	check_eq(t.length(), 64, "256-bit hex token")
	check(ZinoProtocol.tokens_equal(t, t), "equal tokens match")
	check(not ZinoProtocol.tokens_equal(t, t.substr(0, 63) + "x"), "different tokens do not match")
	check(not ZinoProtocol.tokens_equal("", ""), "empty tokens never match")
	check(ZinoProtocol.new_token() != t, "tokens are random")

func test_decode_rejects_garbage() -> void:
	check(ZinoProtocol.decode("not json").is_empty(), "garbage ignored")
	check(ZinoProtocol.decode("[1,2]").is_empty(), "non-object ignored")
	check(ZinoProtocol.decode('{"x":1}').is_empty(), "missing type ignored")
	check_eq(ZinoProtocol.decode('{"type":"event","name":"LOG"}')["type"], "event", "valid message parsed")
