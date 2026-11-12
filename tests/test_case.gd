class_name TestCase
extends RefCounted
## Base class for tests. A test file is tests/test_*.gd, extends TestCase, and
## has methods whose names start with "test_". tests/run_tests.gd runs them.

## The running scene tree, for tests that need to put nodes in it.
var tree: SceneTree
## Failure messages collected by the checks below.
var failures: PackedStringArray = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: got %s, expected %s" % [message, actual, expected])
