class_name Layers
extends RefCounted
## Physics layers (bit values). Named so code never uses magic numbers.

const FLOOR := 1 ## Walkable floor; clicking it moves the character.
const WALLS := 2
const FURNITURE := 4 ## Each solid part of a piece of furniture: blocks the character; not interactable.
const DEVICES := 8 ## Hardware and packages: block walking and are interactable.
const PORTS := 16 ## Port areas, picked only in close-up views.
const SLOTS := 32 ## Rack unit areas, picked only while mounting.
const CHARACTER := 64
const NAV_BLOCK := 128 ## Whole footprint of a piece of furniture, only for baking the navigation.

## The navigation is baked from whole footprints (never from the parts: the floor under a desk
## must not become walkable, and only floor level is baked).
const NAV_OBSTACLES := FLOOR | WALLS | DEVICES | NAV_BLOCK
const WORLD_PICK := FLOOR | FURNITURE | DEVICES
