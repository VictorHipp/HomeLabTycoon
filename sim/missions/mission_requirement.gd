class_name MissionRequirement
extends Resource
## One success criterion of a mission: a validator (a query on the world state, never a
## sequence of actions) plus its parameters. docs/PROGRESSION.md §6.

@export var id: StringName = &""
@export var text: String = "" ## Shown to the player (Spanish source text, gettext style).
@export var validator: StringName = &"" ## Name understood by MissionValidators.check().
@export var params: Dictionary = {}
