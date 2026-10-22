extends Node
## Project-wide signals so UI and gameplay stay decoupled.
signal setting_changed(key: String, value: Variant)
signal level_completed(level_id: String, stars: int)
signal hints_changed(count: int)
signal supporter_changed(active: bool)
signal banner_changed(height: float)
signal purchases_changed
signal keys_changed(count: int)
