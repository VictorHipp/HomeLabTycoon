class_name Economy
extends RefCounted
## Where the credits and the XP come from and where they go (docs/PROGRESSION.md §8, §10.3).
## Every change goes through `record`, which writes one line in the ledger with its reason, so
## the player can always check the account. Also: passive income of equipment that is online on
## the home network (small and capped per day, ADR 0010) and second-hand prices. Pure logic,
## owned by SimWorld; amounts and rates come from data (EconomyRules, catalog).

const RULES_PATH := "res://data/economy/economy_rules.tres"
const MAX_LEDGER := 400 ## Oldest lines are dropped beyond this (the totals keep counting).

var rules: EconomyRules
## {"t": game minutes, "credits": int, "xp": int, "kind": String, "text": String, "count": int}
## kinds: start, purchase, sale, reward, skill, passive.
var ledger: Array[Dictionary] = []
var earned_total: int = 0 ## Credits earned (rewards, sales, passive income; not the starting savings).
var spent_total: int = 0 ## Credits ever spent.
var passive_pending: float = 0.0 ## Earned this hour but not paid yet (money is integer).
var passive_day: int = 0 ## Game day that passive_paid_today belongs to.
var passive_paid_today: int = 0
var passive_paid_total: int = 0
var _earners: Array[int] = [] ## Ids online and paying, cached per world state version.
var _earners_version: int = -1


func _init(rules_to_use: EconomyRules = null) -> void:
	rules = rules_to_use if rules_to_use != null else load(RULES_PATH) as EconomyRules
	if rules == null:
		push_error("Economy: cannot load %s" % RULES_PATH)
		rules = EconomyRules.new()


## Writes a ledger line. Consecutive passive-income lines of the same day are merged into one.
func record(time_minutes: float, credits: int, xp: int, kind: StringName, text: String) -> void:
	if credits > 0 and kind != &"start": # the savings you start with are not earnings
		earned_total += credits
	elif credits < 0:
		spent_total -= credits
	if kind == &"passive" and not ledger.is_empty():
		var last: Dictionary = ledger[ledger.size() - 1]
		if last["kind"] == "passive" and int(last["t"] / 1440.0) == int(time_minutes / 1440.0):
			last["credits"] = int(last["credits"]) + credits
			last["count"] = int(last["count"]) + 1
			last["t"] = time_minutes
			return
	ledger.append({"t": time_minutes, "credits": credits, "xp": xp, "kind": String(kind), "text": text, "count": 1})
	if ledger.size() > MAX_LEDGER:
		ledger.pop_front()


# --------------------------------------------------------------- second hand --

## What the second-hand market pays for a device now (0 = it cannot be sold).
func resale_price(d: SimDevice) -> int:
	if d == null or not d.bought or not d.definition.purchasable or d.definition.price <= 0:
		return 0
	var percent := rules.resale_used_percent if d.used else rules.resale_unused_percent
	return maxi(1, d.definition.price * percent / 100)


# ------------------------------------------------------------ passive income --

## Devices that earn passive income now: equipment with a rate in the catalog that is running
## and reachable both ways from a computer of the player (docs/PROGRESSION.md §8). It is a
## simplification declared in the game: no simulated service runs on them yet.
func earners(world: SimWorld) -> Array[SimDevice]:
	if _earners_version != world.state_version():
		_earners_version = world.state_version()
		_earners.clear()
		var computers := world.devices_of(&"computer")
		for d: SimDevice in world.devices.values():
			if d.definition.online_income_per_hour <= 0 or not d.is_running() or not d.is_in_world():
				continue
			for pc: SimDevice in computers:
				if pc.is_running() and NetworkEngine.reachable(world, pc, d) and NetworkEngine.reachable(world, d, pc):
					_earners.append(d.id)
					break
	var result: Array[SimDevice] = []
	for device_id: int in _earners:
		var d := world.get_device(device_id)
		if d != null:
			result.append(d)
	return result


## Credits per game hour earned now (before the daily cap).
func passive_rate(world: SimWorld) -> int:
	var rate := 0
	for d: SimDevice in earners(world):
		rate += d.definition.online_income_per_hour
	return rate


## Credits that can still be earned today.
func passive_left_today(time_minutes: float) -> int:
	if int(time_minutes / 1440.0) != passive_day:
		return rules.passive_daily_cap
	return maxi(0, rules.passive_daily_cap - passive_paid_today)


## Accrues passive income for `dt` minutes ending at world.time_minutes and pays it on the hour.
## Returns the credits to pay now (SimWorld adds them and writes the ledger).
func accrue(world: SimWorld, dt: float) -> int:
	var now := world.time_minutes
	var day := int(now / 1440.0)
	if day != passive_day:
		passive_day = day
		passive_paid_today = 0
	var rate := passive_rate(world)
	if rate > 0:
		passive_pending += rate * dt / 60.0
	if int(now / 60.0) == int((now - dt) / 60.0):
		return 0 # paid on the hour
	var amount := mini(floori(passive_pending), rules.passive_daily_cap - passive_paid_today)
	passive_pending -= floorf(passive_pending)
	if passive_paid_today + maxi(amount, 0) >= rules.passive_daily_cap:
		passive_pending = 0.0 # nothing more today: it does not pile up for tomorrow
	if amount <= 0:
		return 0
	passive_paid_today += amount
	passive_paid_total += amount
	return amount


# --------------------------------------------------------------- save / load --

func save_state() -> Dictionary:
	return {
		"ledger": ledger.duplicate(true),
		"earned_total": earned_total,
		"spent_total": spent_total,
		"passive_pending": passive_pending,
		"passive_day": passive_day,
		"passive_paid_today": passive_paid_today,
		"passive_paid_total": passive_paid_total,
	}


func load_state(data: Dictionary) -> void:
	ledger.clear()
	for line: Dictionary in data.get("ledger", []):
		ledger.append({"t": float(line["t"]), "credits": int(line["credits"]), "xp": int(line.get("xp", 0)),
			"kind": String(line["kind"]), "text": String(line["text"]), "count": int(line.get("count", 1))})
	earned_total = int(data.get("earned_total", 0))
	spent_total = int(data.get("spent_total", 0))
	passive_pending = float(data.get("passive_pending", 0.0))
	passive_day = int(data.get("passive_day", 0))
	passive_paid_today = int(data.get("passive_paid_today", 0))
	passive_paid_total = int(data.get("passive_paid_total", 0))
	_earners_version = -1
