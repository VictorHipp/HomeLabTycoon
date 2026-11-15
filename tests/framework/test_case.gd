class_name TestCase
extends RefCounted
## Base class for headless unit / integration tests run by tests/run_tests.gd.
## Every method whose name starts with "test_" is executed; before_each() runs first.

var failures: Array[String] = []
var current_test: String = ""


func before_each() -> void:
	pass


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("expected true" if message == "" else message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("expected false" if message == "" else message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_fail("%s: got <%s>, expected <%s>" % [message, str(actual), str(expected)])


func assert_almost(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("%s: got %.5f, expected %.5f ± %.5f" % [message, actual, expected, tolerance])


func assert_contains(haystack: String, needle: String, message: String = "") -> void:
	if not haystack.contains(needle):
		_fail("%s: «%s» not found in:\n%s" % [message, needle, haystack])


func _fail(message: String) -> void:
	failures.append("%s: %s" % [current_test, message])
