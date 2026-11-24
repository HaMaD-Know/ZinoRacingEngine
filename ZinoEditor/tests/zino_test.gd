class_name ZinoTest
extends RefCounted
## Base class for Zino tests. Methods named test_* are run by tests/run_tests.gd.
## A test may be a coroutine (use `await`); `tree` gives access to the SceneTree.

var tree: SceneTree
var failures: PackedStringArray = []
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func check_eq(actual, expected, message: String) -> void:
	checks += 1
	if not (typeof(actual) == typeof(expected) and actual == expected):
		failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s (expected %.4f ± %.4f, got %.4f)" % [message, expected, tolerance, actual])

func temp_dir(name: String) -> String:
	# Inside the repository (on F:), not the user profile: exports can be hundreds of MB.
	var base := ProjectSettings.globalize_path("res://").path_join("../.test_tmp").simplify_path().path_join(name + "_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(base)
	return base

static func remove_dir_recursive(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		remove_dir_recursive(path.path_join(sub))
	DirAccess.remove_absolute(path)
