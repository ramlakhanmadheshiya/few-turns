extends Node
## All ad decisions live here so ads stay polite:
## - a small banner at the very bottom of every screen, with layout space reserved
##   so it never covers buttons;
## - a rewarded ad only when the player agrees to watch one for +1 hint;
## - one full-screen ad after every INTERSTITIAL_EVERY wins, shown only when the
##   player taps Next (never mid-room).
## Supporters see no banners and no full-screen ads, and get free hints.
## Providers: AdMob on Android (plugin), the Brainnova Studio play page in the
## browser (WebPlatform; it decides which ad types this device gets), a visible
## mock on debug desktop builds, and nothing at all elsewhere.

signal rewarded_finished(ok: bool)

## Loaded lazily: it references plugin classes that only matter on Android.
const ADMOB_PROVIDER_PATH: String = "res://game/ads/providers/admob_provider.gd"
const MockProvider: GDScript = preload("res://game/ads/providers/mock_ad_provider.gd")
const WebProvider: GDScript = preload("res://game/ads/providers/web_provider.gd")
const INTERSTITIAL_EVERY: int = 10

var provider: Node = null
var banner_height: float = 0.0
var _banner_on: bool = false


func _ready() -> void:
	if Engine.has_singleton("PoingGodotAdMob"):
		provider = (load(ADMOB_PROVIDER_PATH) as GDScript).new()
	elif WebPlatform.active():
		provider = WebProvider.new()
	elif OS.is_debug_build() and not OS.has_feature("mobile") and not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		provider = MockProvider.new()
	if provider != null:
		provider.name = "AdProvider"
		add_child(provider)
		provider.banner_resized.connect(_on_banner_resized)
	Events.supporter_changed.connect(func(_on: bool) -> void: refresh_banner())
	Events.level_completed.connect(func(_id: String, _stars: int) -> void:
		SaveSystem.set_wins_since_ad(SaveSystem.wins_since_ad() + 1)
	)


func ads_enabled() -> bool:
	return provider != null and not SaveSystem.is_supporter()


## Shows the bottom banner unless the player is a supporter.
func refresh_banner() -> void:
	var want: bool = ads_enabled()
	if want == _banner_on:
		return
	_banner_on = want
	if provider == null:
		return
	if want:
		provider.show_banner()
	else:
		provider.hide_banner()
		_on_banner_resized(0.0)


func _on_banner_resized(height_px: float) -> void:
	# Convert device pixels to viewport units so layouts can reserve the space.
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	var vp: Vector2 = get_viewport().get_visible_rect().size
	banner_height = height_px * (vp.y / maxf(1.0, win.y)) if height_px > 0.0 else 0.0
	Events.banner_changed.emit(banner_height)


func rewarded_ready() -> bool:
	return provider != null and provider.rewarded_ready()


## Plays a rewarded ad; callback(ok) is true if the reward was earned, or if the
## ad could not be shown at all (the player then gets the hint free).
func show_rewarded(callback: Callable) -> void:
	if not rewarded_ready():
		callback.call(false)
		return
	provider.show_rewarded(func(ok: bool) -> void:
		rewarded_finished.emit(ok)
		callback.call(ok)
	)


## Between levels: after every INTERSTITIAL_EVERY wins, shows a full-screen ad and
## then calls go. Otherwise (or for supporters, or with no ad loaded) calls go at once.
func between_levels(go: Callable) -> void:
	if not ads_enabled() or SaveSystem.wins_since_ad() < INTERSTITIAL_EVERY or not provider.interstitial_ready():
		go.call()
		return
	SaveSystem.set_wins_since_ad(0)
	provider.show_interstitial(go)
