class_name MissionTracker
extends RefCounted
## Live state of one mission: which requirements pass now, which ones already gave their XP, and
## whether it was completed. Every reward is granted exactly once: a requirement's XP the first
## time it is met (undoing and redoing it gives nothing), the mission reward on completion.

var definition: MissionDefinition
var status: Array[bool] = []
var rewarded: Array[bool] = [] ## Requirement XP already granted.
var completed: bool = false


func _init(def: MissionDefinition) -> void:
	definition = def
	for _req: MissionRequirement in def.requirements:
		rewarded.append(false)


## XP of the whole mission: every requirement plus the completion reward.
func total_xp() -> int:
	var total := definition.reward_xp
	for req: MissionRequirement in definition.requirements:
		total += req.xp
	return total


## Serialisable state. `completed` and `rewarded` are saved so no reward is granted twice.
func save_state() -> Dictionary:
	return {"definition": definition.resource_path, "status": status.duplicate(),
		"rewarded": rewarded.duplicate(), "completed": completed}


static func from_state(data: Dictionary) -> MissionTracker:
	var def := load(String(data["definition"])) as MissionDefinition
	if def == null:
		push_error("MissionTracker: cannot load %s" % data["definition"])
		return null
	var tracker := MissionTracker.new(def)
	for value: Variant in data.get("status", []):
		tracker.status.append(bool(value))
	tracker.completed = bool(data.get("completed", false))
	var saved: Array = data.get("rewarded", [])
	for i: int in tracker.rewarded.size():
		# Saves of version 1: a completed mission had already paid all its XP.
		tracker.rewarded[i] = bool(saved[i]) if i < saved.size() else tracker.completed
	return tracker


func evaluate(world: SimWorld) -> void:
	var new_status: Array[bool] = []
	for req: MissionRequirement in definition.requirements:
		new_status.append(MissionValidators.check(world, req.validator, req.params))
	if new_status != status:
		status = new_status
		world.emit_event(&"mission_progress", {"mission_id": definition.id})
	for i: int in status.size():
		if status[i] and not rewarded[i]:
			rewarded[i] = true
			var req := definition.requirements[i]
			if req.xp > 0:
				world.grant_rewards(0, req.xp, &"skill", tr("Objetivo cumplido: %s") % tr(req.text))
	if not completed and not status.is_empty() and not status.has(false):
		completed = true
		world.grant_rewards(definition.reward_credits, definition.reward_xp, &"reward",
			tr("Misión completada: %s") % tr(definition.title))
		world.emit_event(&"mission_completed", {"mission_id": definition.id,
			"credits": definition.reward_credits, "xp": total_xp()})
