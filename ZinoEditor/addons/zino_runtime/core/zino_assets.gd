@tool
class_name ZinoAssets
extends RefCounted
## Loads project assets at runtime: textures/HDRIs from the project folder in the editor, or the
## Godot-imported resources (res://) in exported games. Paths must stay inside the project.

static var _textures := {}

static func safe(rel: String) -> bool:
	var p := rel.replace("\\", "/")
	return p != "" and not p.contains("..") and not p.begins_with("/") and not (p.contains(":") and not p.begins_with("res://"))

static func load_texture(rel: String) -> Texture2D:
	if not safe(rel):
		return null
	if _textures.has(rel):
		return _textures[rel]
	var tex: Texture2D = null
	var root := ZinoModelLoader.project_root
	if root == "":
		var res := rel if rel.begins_with("res://") else "res://" + rel
		if ResourceLoader.exists(res):
			tex = load(res) as Texture2D
	else:
		var full := root.path_join(rel)
		if FileAccess.file_exists(full):
			var img := Image.load_from_file(full)
			if img:
				if not rel.get_extension().to_lower() in ["hdr", "exr"]:
					img.generate_mipmaps()
				tex = ImageTexture.create_from_image(img)
	if tex:
		_textures[rel] = tex
	return tex

static func clear_cache() -> void:
	_textures.clear()
