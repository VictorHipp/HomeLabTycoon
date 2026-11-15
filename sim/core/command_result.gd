class_name CommandResult
extends RefCounted
## Outcome of a player command: ok, or rejected with a reason the player can read.

var ok: bool = true
var message: String = ""
var data: Variant = null


static func success(text: String = "", payload: Variant = null) -> CommandResult:
	var r := CommandResult.new()
	r.message = text
	r.data = payload
	return r


static func failure(text: String) -> CommandResult:
	var r := CommandResult.new()
	r.ok = false
	r.message = text
	return r
