class_name MissionDefinition
extends Resource
## A mission or contract (docs/PROGRESSION.md §6). Data only; one `.tres` per mission.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var context: String = ""
@export var budget_note: String = ""
## What the player reads when the mission is completed, after the title and the rewards.
@export_multiline var completion_text: String = ""
@export var reward_credits: int = 0
@export var reward_xp: int = 0 ## On completion, on top of the XP of each requirement.
@export var requirements: Array[MissionRequirement] = []
