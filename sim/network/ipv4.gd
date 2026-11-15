class_name IPv4
extends RefCounted
## IPv4 helpers on 32-bit integers (dotted-quad text, CIDR prefixes).

const ALL_ONES := 0xFFFFFFFF


## "192.168.1.50" -> int, or -1 if invalid.
static func parse(text: String) -> int:
	var parts := text.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var value := 0
	for part: String in parts:
		if part.is_empty() or not part.is_valid_int():
			return -1
		var octet := part.to_int()
		if octet < 0 or octet > 255:
			return -1
		value = (value << 8) | octet
	return value


## "192.168.1.50/24" -> [ip, prefix]; [] if invalid. A bare address means /32.
static func parse_cidr(text: String) -> Array[int]:
	var pieces := text.strip_edges().split("/")
	if pieces.size() > 2:
		return []
	var ip := parse(pieces[0])
	if ip < 0:
		return []
	var prefix := 32
	if pieces.size() == 2:
		if not pieces[1].is_valid_int():
			return []
		prefix = pieces[1].to_int()
		if prefix < 0 or prefix > 32:
			return []
	return [ip, prefix]


static func format(ip: int) -> String:
	return "%d.%d.%d.%d" % [(ip >> 24) & 255, (ip >> 16) & 255, (ip >> 8) & 255, ip & 255]


static func mask(prefix: int) -> int:
	if prefix <= 0:
		return 0
	return (ALL_ONES << (32 - prefix)) & ALL_ONES


static func network(ip: int, prefix: int) -> int:
	return ip & mask(prefix)


static func broadcast(ip: int, prefix: int) -> int:
	return network(ip, prefix) | (~mask(prefix) & ALL_ONES)


static func in_subnet(ip: int, subnet_ip: int, prefix: int) -> bool:
	return network(ip, prefix) == network(subnet_ip, prefix)


static func is_loopback(ip: int) -> bool:
	return (ip >> 24) == 127
