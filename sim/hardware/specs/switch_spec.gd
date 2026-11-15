class_name SwitchSpec
extends Resource
## Capability: Ethernet switching between the ports of `port_group` (one broadcast domain;
## VLANs come with managed switches in stage 2).

@export var port_group: StringName = &"lan"
@export var managed: bool = false
