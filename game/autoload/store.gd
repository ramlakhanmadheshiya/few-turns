extends Node
## In-app purchases: the shop's catalogue and Google Play Billing.
## On Android this uses the Google Play Billing plugin; elsewhere purchases are
## unavailable, except debug desktop builds, which simulate them so the flow can
## be tested. Every product id here must also exist in the Play Console.

signal purchase_finished(ok: bool, message: String, product: String)
signal restore_finished(found: bool, message: String)
signal price_updated(product: String, price: String)

## Shop order. "tier" picks the fallback price shown until Google Play answers.
const PRODUCTS: Dictionary = {
	"complete_pack": {"name": "Complete pack", "tier": 3, "blurb": "Everything below, plus 5 level keys",
		"perks": ["No ads, every hint free", "6 orb styles with their own trails", "11 colour themes", "5 level keys to open any room", "Yours to keep after one purchase"]},
	"supporter_pack": {"name": "Supporter pack", "tier": 2, "blurb": "No ads, and every hint free",
		"perks": ["No ads", "Every hint free, always", "Helps new chapters get made"]},
	"orb_pack": {"name": "Orb pack", "tier": 1, "blurb": "Comet, Ember, Neon and 3 more", "trial": true,
		"perks": ["6 more orbs, each with its own trail", "Pick one any time in Settings", "Yours to keep after one purchase"]},
	"theme_pack": {"name": "Theme pack", "tier": 1, "blurb": "Midnight, Nord, Sepia and 8 more", "trial": true,
		"perks": ["11 colour themes, light and dark", "Pick one any time in Settings", "Yours to keep after one purchase"]},
}
## Level keys: consumable, one opens any locked room. Sold 1-10 at a time as
## products keys_1 ... keys_10; five or more get 10% off.
const KEY_MAX: int = 10
const KEY_BULK: int = 5
const KEY_DISCOUNT: float = 0.10
## Per-key fallback price by region: [symbol, amount, decimals, symbol after].
const KEY_UNIT: Dictionary = {
	"IN": ["₹", 30.0, 0], "US": ["$", 0.49, 2], "EU": ["€", 0.49, 2], "GB": ["£", 0.39, 2],
	"CA": ["CA$", 0.69, 2], "AU": ["A$", 0.79, 2], "JP": ["¥", 80.0, 0], "BR": ["R$", 2.49, 2],
	"ID": ["Rp ", 7500.0, 0], "PK": ["Rs ", 129.0, 0], "BD": ["৳", 49.0, 0], "NP": ["Rs ", 59.0, 0],
	"PH": ["₱", 25.0, 0], "TR": ["₺", 15.99, 2], "MX": ["MX$", 9.0, 0],
}
## Tip jar: consumable, opens nothing. Preset amounts plus any custom amount in
## steps of 10 up to 1,000, then steps of 100 up to 10,000 (Google Play sells fixed
## prices, so each amount is its own product, tip_10 ... tip_10000, priced in rupees
## and converted by Play elsewhere).
const TIP_PRESETS: Array = [20, 50, 100, 200]
const TIP_MIN: int = 10
const TIP_MAX: int = 10000
const TIP_STEP: int = 10
const TIP_BIG_FROM: int = 1000
const TIP_BIG_STEP: int = 100

## Fallback prices by tier, per region, kept in line with the Play Console.
## Tiers: 0 = $0.99, 1 = $1.99, 2 = $2.99, 3 = $5.99, 4 = $9.99, 5 = $19.99.
const REGIONAL_TIERS: Dictionary = {
	"US": ["$0.99", "$1.99", "$2.99", "$5.99", "$9.99", "$19.99"],
	"IN": ["₹79", "₹149", "₹249", "₹449", "₹799", "₹1,599"],
	"GB": ["£0.89", "£1.79", "£2.49", "£4.99", "£8.99", "£17.99"],
	"CA": ["CA$1.39", "CA$2.79", "CA$3.99", "CA$7.99", "CA$13.99", "CA$27.99"],
	"AU": ["A$1.49", "A$2.99", "A$4.49", "A$8.99", "A$15.99", "A$29.99"],
	"EU": ["€0.99", "€1.99", "€2.99", "€5.99", "€9.99", "€19.99"],
	"JP": ["¥160", "¥300", "¥450", "¥900", "¥1,500", "¥3,000"],
	"BR": ["R$4,90", "R$9,90", "R$14,90", "R$29,90", "R$49,90", "R$99,90"],
	"ID": ["Rp 15.000", "Rp 29.000", "Rp 45.000", "Rp 89.000", "Rp 149.000", "Rp 299.000"],
	"PK": ["Rs 249", "Rs 499", "Rs 799", "Rs 1,599", "Rs 2,699", "Rs 5,399"],
	"BD": ["৳99", "৳199", "৳299", "৳599", "৳999", "৳1,999"],
	"NP": ["Rs 129", "Rs 259", "Rs 399", "Rs 799", "Rs 1,299", "Rs 2,599"],
	"PH": ["₱49", "₱99", "₱149", "₱299", "₱499", "₱999"],
	"TR": ["₺34,99", "₺64,99", "₺99,99", "₺199,99", "₺329,99", "₺649,99"],
	"MX": ["MX$19", "MX$39", "MX$59", "MX$119", "MX$199", "MX$399"],
}
const EURO_REGIONS: Array = ["DE", "FR", "IT", "ES", "NL", "BE", "AT", "IE", "PT", "FI", "GR", "SK"]

var prices: Dictionary = {}
var _billing: BillingClient = null
var _restoring: bool = false


func _ready() -> void:
	for id: String in PRODUCTS:
		prices[id] = regional_price(tier_of(id))
	for n: int in range(1, KEY_MAX + 1):
		prices["keys_%d" % n] = keys_price(n)
	for n: int in tip_amounts():
		prices["tip_%d" % n] = tip_price(n)
	# Only create the client where the native plugin exists (Android builds).
	if Engine.has_singleton("GodotGooglePlayBilling"):
		_billing = BillingClient.new()
		add_child(_billing)
		_connect_billing()


static func key_ids() -> Array:
	var out: Array = []
	for n: int in range(1, KEY_MAX + 1):
		out.append("keys_%d" % n)
	return out


static func tip_ids() -> Array:
	var out: Array = []
	for n: int in tip_amounts():
		out.append("tip_%d" % n)
	return out


## Every amount sold as a tip, in rupees.
static func tip_amounts() -> Array:
	var out: Array = range(TIP_MIN, TIP_BIG_FROM + 1, TIP_STEP)
	out.append_array(range(TIP_BIG_FROM + TIP_BIG_STEP, TIP_MAX + 1, TIP_BIG_STEP))
	return out


## The nearest amount that exists as a product.
static func snap_tip(rupees: int) -> int:
	var step: int = TIP_STEP if rupees <= TIP_BIG_FROM else TIP_BIG_STEP
	var r: int = int(round(float(rupees) / float(step))) * step
	return clampi(r, TIP_MIN, TIP_MAX)


## The next amount up (dir 1) or down (dir -1) from a valid amount.
static func nudge_tip(rupees: int, dir: int) -> int:
	var step: int = TIP_BIG_STEP if (rupees > TIP_BIG_FROM or (rupees == TIP_BIG_FROM and dir > 0)) else TIP_STEP
	return clampi(rupees + dir * step, TIP_MIN, TIP_MAX)


static func all_ids() -> Array:
	return PRODUCTS.keys() + key_ids() + tip_ids()


static func is_tip(product: String) -> bool:
	return product.begins_with("tip_")


static func is_keys(product: String) -> bool:
	return product.begins_with("keys_")


static func key_count(product: String) -> int:
	return int(product.trim_prefix("keys_"))


static func tier_of(product: String) -> int:
	return int(PRODUCTS.get(product, {}).get("tier", 0))


static func _money(unit: Array, amount: float) -> String:
	var dec: int = int(unit[2])
	var num: String = str(int(round(amount))) if dec == 0 else ("%.2f" % amount)
	return str(unit[0]) + num


## Fallback price for n keys (Play's real price replaces it once known).
static func keys_price(n: int) -> String:
	var unit: Array = KEY_UNIT.get(_region(), KEY_UNIT["US"])
	var each: float = float(unit[1]) * (1.0 - KEY_DISCOUNT if n >= KEY_BULK else 1.0)
	return _money(unit, each * float(n))


## Fallback price of a tip of `rupees` (shown as rupees in India, else converted
## roughly from the key price ratio).
static func tip_price(rupees: int) -> String:
	if _region() == "IN":
		return "₹%d" % rupees
	var unit: Array = KEY_UNIT.get(_region(), KEY_UNIT["US"])
	return _money(unit, float(unit[1]) * float(rupees) / 30.0)


static func display_name(product: String) -> String:
	return str(PRODUCTS.get(product, {}).get("name", "Tip"))


static func _region() -> String:
	var parts: PackedStringArray = OS.get_locale().replace("-", "_").split("_")
	for i: int in range(parts.size() - 1, 0, -1):
		var region: String = parts[i].to_upper()
		if REGIONAL_TIERS.has(region):
			return region
		if EURO_REGIONS.has(region):
			return "EU"
	return "US"


## Best-guess local price for a tier from the device locale, e.g. "en_IN" -> "₹249".
static func regional_price(tier: int = 2) -> String:
	return str(REGIONAL_TIERS[_region()][tier])


func price(product: String) -> String:
	return str(prices.get(product, regional_price(tier_of(product))))


## How much the Complete pack saves over buying its parts (supporter, orbs,
## themes and 5 keys), as a percentage of US fallback prices.
static func complete_saving() -> int:
	var us: Array = REGIONAL_TIERS["US"]
	var parts: float = 0.0
	for id: String in ["supporter_pack", "orb_pack", "theme_pack"]:
		parts += float(str(us[tier_of(id)]).trim_prefix("$"))
	parts += float(KEY_UNIT["US"][1]) * 5.0 * (1.0 - KEY_DISCOUNT)
	var whole: float = float(str(us[tier_of("complete_pack")]).trim_prefix("$"))
	return int(round((1.0 - whole / parts) * 100.0))


func available() -> bool:
	return _billing != null or _simulated()


func _simulated() -> bool:
	return OS.is_debug_build() and not OS.has_feature("mobile") and not OS.has_feature("web")


func buy(product: String) -> void:
	if PRODUCTS.has(product) and SaveSystem.bought(product):
		purchase_finished.emit(true, "It's already yours. Thank you!", product)
		return
	if _billing != null:
		_billing_buy(product)
	elif _simulated():
		_grant(product)
		purchase_finished.emit(true, "Thank you! (simulated purchase in a debug build)", product)
	else:
		purchase_finished.emit(false, "Purchases are available in the Android app.", product)


func restore() -> void:
	if _billing != null:
		_billing_restore()
	elif _simulated():
		var any: bool = false
		for id: String in PRODUCTS:
			any = any or SaveSystem.bought(id)
		restore_finished.emit(any, "Restored." if any else "No purchase found.")
	else:
		restore_finished.emit(false, "Restore is available in the Android app.")


func _grant(product: String) -> void:
	if is_tip(product):
		SaveSystem.add_tip(int(product.trim_prefix("tip_")))
	elif is_keys(product):
		SaveSystem.add_keys(key_count(product))
	else:
		SaveSystem.set_owned(product, true)


# --- Google Play Billing -------------------------------------------------------

func _connect_billing() -> void:
	_billing.connected.connect(func() -> void:
		_billing.query_product_details(PackedStringArray(all_ids()), BillingClient.ProductType.INAPP)
		# Silent restore on every launch keeps entitlements in sync.
		_billing.query_purchases(BillingClient.ProductType.INAPP)
	)
	_billing.connect_error.connect(func(code: int, msg: String) -> void: push_warning("Billing %d %s" % [code, msg]))
	_billing.query_product_details_response.connect(func(res: Dictionary) -> void:
		if int(res.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
			return
		for p: Dictionary in res.get("product_details", []):
			var offers: Variant = p.get("one_time_purchase_offer_details_list")
			var id: String = str(p.get("product_id", ""))
			if prices.has(id) and offers is Array and not (offers as Array).is_empty():
				prices[id] = str(offers[0].get("formatted_price", prices[id]))
				price_updated.emit(id, prices[id])
	)
	_billing.query_purchases_response.connect(_on_purchases)
	_billing.on_purchase_updated.connect(_on_purchases)
	_billing.start_connection()


func _billing_buy(product: String) -> void:
	if not _billing.is_ready():
		purchase_finished.emit(false, "Can't reach Google Play right now. Try again in a moment.", product)
		return
	var res: Dictionary = _billing.purchase(product)
	if int(res.get("response_code", -1)) != BillingClient.BillingResponseCode.OK:
		purchase_finished.emit(false, "Purchase couldn't start (%s)." % str(res.get("debug_message", "unknown")), product)


func _billing_restore() -> void:
	if not _billing.is_ready():
		restore_finished.emit(false, "Can't reach Google Play right now. Try again in a moment.")
		return
	_restoring = true
	_billing.query_purchases(BillingClient.ProductType.INAPP)


func _on_purchases(res: Dictionary) -> void:
	var code: int = int(res.get("response_code", -1))
	if code == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED:
		_restoring = true
		_billing.query_purchases(BillingClient.ProductType.INAPP)
		return
	if code != BillingClient.BillingResponseCode.OK:
		if code == BillingClient.BillingResponseCode.USER_CANCELED:
			purchase_finished.emit(false, "Purchase cancelled.", "")
		elif _restoring:
			_restoring = false
			restore_finished.emit(false, "Couldn't check purchases. Try again later.")
		return
	var found: int = 0
	for p: Dictionary in res.get("purchases", []):
		if int(p.get("purchase_state", 0)) != BillingClient.PurchaseState.PURCHASED:
			continue
		for id: String in p.get("product_ids", []):
			if is_tip(id) or is_keys(id):
				# Tips and keys are consumed so they can be bought again.
				_billing.consume_purchase(str(p["purchase_token"]))
				_grant(id)
				var msg: String = "Thank you so much for the tip ♥" if is_tip(id) else "%d %s added" % [key_count(id), "key" if key_count(id) == 1 else "keys"]
				purchase_finished.emit(true, msg, id)
			elif PRODUCTS.has(id):
				found += 1
				if not bool(p.get("is_acknowledged", false)):
					_billing.acknowledge_purchase(str(p["purchase_token"]))
				if not SaveSystem.bought(id):
					_grant(id)
					purchase_finished.emit(true, "Thank you for supporting Few Turns!", id)
	if _restoring:
		_restoring = false
		restore_finished.emit(found > 0, "Purchases restored." if found > 0 else "No previous purchase found on this Google account.")
