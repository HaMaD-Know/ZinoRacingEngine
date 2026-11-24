@tool
class_name ZinoModelLoader
extends RefCounted
## Loads 3D models (GLB, glTF, FBX) for vehicles and props.
## In exported games models are Godot-imported resources (res://…); in the Zino Editor they are read
## directly from the project folder with Godot's runtime glTF/FBX importers. Source files are never modified.

const EXTENSIONS := ["glb", "gltf", "fbx"]
static var project_root := ""          # absolute project path in the editor; "" in exported games
static var _cache := {}

static func clear_cache() -> void:
	_cache.clear()

## Returns a new instance of the model's scene, or {error} on failure.
static func instantiate(rel_path: String) -> Dictionary:
	var p := rel_path.replace("\\", "/")
	if p.contains("..") or p.begins_with("/") or (p.contains(":") and not p.begins_with("res://")):
		return {"error": "model paths must be inside the project"}
	if not p.get_extension().to_lower() in EXTENSIONS:
		return {"error": "unsupported model format: " + p.get_extension()}
	if _cache.has(p):
		return {"node": (_cache[p] as PackedScene).instantiate()}
	var res_path := p if p.begins_with("res://") else "res://" + p
	var packed: PackedScene = null
	if project_root == "" and ResourceLoader.exists(res_path):
		packed = load(res_path) as PackedScene
	else:
		var full := project_root.path_join(p) if project_root != "" else ProjectSettings.globalize_path(res_path)
		if not FileAccess.file_exists(full):
			return {"error": "model not found: " + p}
		var doc: GLTFDocument = FBXDocument.new() if p.get_extension().to_lower() == "fbx" else GLTFDocument.new()
		var state: GLTFState = FBXState.new() if doc is FBXDocument else GLTFState.new()
		var err := doc.append_from_file(full, state)
		if err != OK:
			return {"error": "could not read %s (error %d)" % [p, err]}
		var root := doc.generate_scene(state)
		if root == null:
			return {"error": "could not build a scene from " + p}
		packed = PackedScene.new()
		_set_owner(root, root)
		packed.pack(root)
		root.free()
	if packed == null:
		return {"error": "could not load " + p}
	_cache[p] = packed
	return {"node": packed.instantiate()}

static func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)

## Mesh nodes of a model as {path: MeshInstance3D}, paths relative to the model root.
static func mesh_nodes(model: Node) -> Dictionary:
	var out := {}
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out[str(model.get_path_to(n))] = n
		for c in n.get_children():
			stack.append(c)
	return out

## Guesses which mesh is which wheel from node names (FL/FR/RL/RR, front_left, wheel_lf, ...).
static func detect_wheels(model: Node) -> Dictionary:
	var found := {}
	var patterns := {
		"FL": ["fl", "frontleft", "front_l", "lf", "leftfront", "wheel_fl", "wheelfl"],
		"FR": ["fr", "frontright", "front_r", "rf", "rightfront", "wheel_fr", "wheelfr"],
		"RL": ["rl", "rearleft", "rear_l", "lr", "leftrear", "bl", "backleft", "wheel_rl", "wheelrl"],
		"RR": ["rr", "rearright", "rear_r", "rightrear", "br", "backright", "wheel_rr", "wheelrr"],
	}
	for path in mesh_nodes(model):
		var flat := str(path).to_lower().replace(" ", "").replace("-", "").replace(".", "")
		if not (flat.contains("wheel") or flat.contains("tire") or flat.contains("tyre") or flat.contains("rim")):
			continue
		var leaf := flat.get_file()
		for key in patterns:
			if found.has(key):
				continue
			for pat in patterns[key]:
				if leaf.ends_with(pat) or leaf.contains("_" + pat) or leaf.begins_with(pat + "_") or leaf.contains(pat.replace("_", "")):
					found[key] = path
					break
	return found

## AABB of a node and its children in the coordinate space of `space`.
static func aabb_in(node: Node3D, space: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var inv := space.global_transform.affine_inverse()
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D:
			var b := inv * (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in n.get_children():
			stack.append(c)
	return out
