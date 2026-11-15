extends TestCase
## Terminal behaviour and honesty rules (docs/TERMINAL_DESIGN.md §6, decision 9–10).

var world: SimWorld
var pc: SimDevice


func before_each() -> void:
	world = BedroomScenario.create()
	pc = world.devices_of(&"computer")[0]


func _run(line: String, user: String = "jugador") -> String:
	return Shell.new(pc.id, user).run(world, line)["output"]


func test_pc_got_dhcp_address() -> void:
	var out := _run("ip address show")
	assert_contains(out, "eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>", "eth0 up with carrier")
	assert_contains(out, "inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic eth0", "DHCP lease")
	assert_contains(_run("ip route"), "default via 192.168.1.1 dev eth0 proto dhcp", "default route from DHCP")


func test_ping_router_and_internet() -> void:
	assert_contains(_run("ping -c 1 192.168.1.1"), "1 packets transmitted, 1 received", "router answers")
	assert_contains(_run("ping -c 1 198.51.100.7"), "ttl=117", "simulated Internet answers")
	assert_contains(_run("ping -c 1 192.168.1.77"), "Destination Host Unreachable", "nobody has .77")


func test_ping_without_count_is_honest() -> void:
	assert_contains(_run("ping 192.168.1.1"), "Nota del juego", "explains the simplification")


func test_name_resolution_is_honest() -> void:
	assert_contains(_run("ping -c 1 servidor"), "aún no está simulada", "DNS not simulated yet")


func test_permissions() -> void:
	assert_contains(_run("ip address add 192.168.1.9/24 dev eth0"), "Operation not permitted", "non-root cannot change addresses")


func test_honest_unimplemented_and_unknown() -> void:
	assert_contains(_run("ls -la"), "aún no está implementada", "real command not implemented")
	assert_contains(_run("frobnicate"), "orden no encontrada", "unknown command")
	assert_contains(_run("ip a | grep inet"), "aún no están implementados", "pipes not implemented")
	assert_contains(_run("ping -i 2 192.168.1.1"), "existe en la herramienta real", "known option not implemented")
	assert_contains(_run("echo \"hola"), "comillas", "unclosed quote")


func test_ip_errors_imitate_iproute2() -> void:
	assert_contains(_run("ip foo"), "Object \"foo\" is unknown", "unknown object")
	assert_contains(_run("ip address add 192.168.1.9/24 dev eth9", "root"), "Cannot find device \"eth9\"", "unknown device")
	assert_contains(_run("ip address add 300.1.1.1/24 dev eth0", "root"), "any valid prefix is expected", "bad address")


func test_sequences() -> void:
	assert_eq(_run("echo uno; echo dos"), "uno\ndos", "; runs both")
	assert_eq(_run("frobnicate && echo no"), "bash: frobnicate: orden no encontrada", "&& stops on error")
	assert_contains(_run("frobnicate || echo si"), "si", "|| runs on error")
