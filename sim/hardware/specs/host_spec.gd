class_name HostSpec
extends Resource
## Capability: the device runs a simulated operating system (docs/TERMINAL_DESIGN.md §3).

@export var os_name: String = "HomeLab OS 1.0"
@export var hostname: String = "host"
@export var login_user: String = "jugador" ## User of the local console / desktop session.
## Configuration applied to eth0 at boot: dhcp | none (no address until the player sets one).
@export var eth0_mode: StringName = &"none"
