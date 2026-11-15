class_name PortDefinition
extends Resource
## A group of identical physical ports on one piece of hardware
## (e.g. "24 x RJ45 at 1 Gbps"). Static data only: live link state belongs to
## the simulation, never to this resource.

enum Kind {
	RJ45, ## Copper Ethernet.
	SFP, ## 1 Gbps cage.
	SFP_PLUS, ## 10 Gbps cage.
	SFP28, ## 25 Gbps cage.
	QSFP_PLUS, ## 40 Gbps cage.
	QSFP28, ## 100 Gbps cage.
	POWER_C14, ## AC power inlet.
	POWER_C13, ## AC power outlet (PDU / UPS).
}

@export var id: StringName = &"" ## Unique within the owning hardware, e.g. &"lan", &"uplink".
@export var kind: Kind = Kind.RJ45
@export var count: int = 1 ## How many ports of this kind in the group.
@export var speed_mbps: int = 1000 ## Nominal maximum speed. 0 for power ports.
@export var poe_budget_watts: float = 0.0 ## Total PoE budget offered by the group (0 = no PoE).
## Side of the device where the sockets are: front (+Z of the model), rear (-Z) or top (+Y).
## Must match the model markers (checked by tests/unit/test_catalog.gd). Used to route cables.
@export var face: StringName = &"rear"
## Height of the sockets above the bottom of the device, in metres (cable lengths).
@export var height_m: float = 0.0
