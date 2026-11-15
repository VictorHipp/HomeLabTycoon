class_name RouterSpec
extends Resource
## Capability: home router. Its LAN ports form one bridge with this address,
## it serves DHCP on the LAN and (if `has_internet`) reaches the simulated Internet.

@export var lan_address: String = "192.168.1.1/24"
@export var dhcp_first_host: int = 100 ## First host number of the DHCP pool (192.168.1.100).
@export var dhcp_last_host: int = 199
@export var has_internet: bool = true ## The WAN line from the ISP (outside the room) is up.
