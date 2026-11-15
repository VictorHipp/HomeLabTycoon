class_name Layers
extends RefCounted
## Physics layer bits used by the presentation (picking, navigation, character collisions).

const FLOOR := 1 ## Walkable floor; clicking it moves the character.
const WALLS := 2
const FURNITURE := 4 ## Blocks walking; not interactable.
const DEVICES := 8 ## Hardware and packages: block walking and are interactable.
const PORTS := 16 ## Port areas, picked only in close-up views.
const SLOTS := 32 ## Rack unit areas, picked only while mounting.
const CHARACTER := 64

const NAV_OBSTACLES := FLOOR | WALLS | FURNITURE | DEVICES
const WORLD_PICK := FLOOR | FURNITURE | DEVICES
