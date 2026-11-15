extends TestCase


func test_parse_and_format_round_trip() -> void:
	assert_eq(IPv4.format(IPv4.parse("192.168.1.50")), "192.168.1.50", "round trip")
	assert_eq(IPv4.parse("256.1.1.1"), -1, "octet out of range")
	assert_eq(IPv4.parse("1.2.3"), -1, "three octets")
	assert_eq(IPv4.parse("a.b.c.d"), -1, "not numbers")


func test_cidr() -> void:
	var c := IPv4.parse_cidr("10.0.0.7/8")
	assert_eq(c, [IPv4.parse("10.0.0.7"), 8], "cidr parse")
	assert_eq(IPv4.parse_cidr("10.0.0.7/33"), [], "prefix > 32")
	assert_eq(IPv4.parse_cidr("10.0.0.7")[1], 32, "bare address is /32")


func test_subnets() -> void:
	var ip := IPv4.parse("192.168.1.50")
	assert_eq(IPv4.format(IPv4.network(ip, 24)), "192.168.1.0", "network")
	assert_eq(IPv4.format(IPv4.broadcast(ip, 24)), "192.168.1.255", "broadcast")
	assert_true(IPv4.in_subnet(IPv4.parse("192.168.1.200"), ip, 24), "same /24")
	assert_false(IPv4.in_subnet(IPv4.parse("192.168.2.1"), ip, 24), "different /24")
	assert_true(IPv4.is_loopback(IPv4.parse("127.0.0.1")), "loopback")
