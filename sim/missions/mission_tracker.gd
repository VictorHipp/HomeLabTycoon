class_name MissionTracker
extends RefCounted
## Live state of one mission: which requirements pass now, and whether it was completed
## (rewards are granted exactly once).

var definition: MissionDefinition
var status: Array[bool] = []
var completed: bool = false


func _init(def: MissionDefinition) -> void:
	definition = def


func evaluate(world: SimWorld) -> void:
	var new_status: Array[bool] = []
	for req: MissionRequirement in definition.requirements:
		new_status.append(MissionValidators.check(world, req.validator, req.params))
	if new_status != status:
		status = new_status
		world.emit_event(&"mission_progress", {"mission_id": definition.id})
	if not completed and not status.is_empty() and not status.has(false):
		completed = true
		world.grant_rewards(definition.reward_credits, definition.reward_xp)
		world.emit_event(&"mission_completed", {"mission_id": definition.id,
			"credits": definition.reward_credits, "xp": definition.reward_xp})
