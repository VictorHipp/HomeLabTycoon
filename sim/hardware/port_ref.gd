class_name PortRef
extends RefCounted
## Port identity as a plain string "<device_id>:<group>:<index>" (serialisable, comparable).

static func make(device_id: int, group: StringName, index: int) -> String:
	return "%d:%s:%d" % [device_id, group, index]


static func device_id(ref: String) -> int:
	return ref.get_slice(":", 0).to_int()


static func group(ref: String) -> StringName:
	return StringName(ref.get_slice(":", 1))


static func index(ref: String) -> int:
	return ref.get_slice(":", 2).to_int()


## Name of the model marker for this port (docs/ART_STYLE.md §8).
static func marker_name(kind: PortDefinition.Kind, group_id: StringName, port_index: int) -> String:
	match kind:
		PortDefinition.Kind.POWER_C14:
			return "POWER_IN_%d" % (port_index + 1)
		PortDefinition.Kind.POWER_C13:
			return "POWER_OUT_%d" % (port_index + 1)
		_:
			return "PORT_%s_%d" % [group_id, port_index]
