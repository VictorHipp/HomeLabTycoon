class_name EconomyRules
extends Resource
## Tunable figures of the economy (docs/PROGRESSION.md §8; ADR 0010). Data, not code:
## res://data/economy/economy_rules.tres. Prices and per-item income rates live in the catalog.

## Second-hand market: share of the shop price paid for an item never installed...
@export_range(0, 100) var resale_unused_percent: int = 60
## ...and for one that was installed or plugged in at least once.
@export_range(0, 100) var resale_used_percent: int = 45
## Most passive income (all online equipment together) paid in one game day.
@export var passive_daily_cap: int = 60
