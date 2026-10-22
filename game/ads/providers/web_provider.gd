extends Node
## Ads in the browser, through the Brainnova Studio play page (window.Brainnova.ads).
## The page owns the actual network (AdSense, H5 Games Ads, or our own "house"
## strip until one is set up); this only asks it for each ad. Same place as on
## Android: a bottom banner with space reserved, rewarded on request, and a
## full-screen ad between levels only where WebPlatform allows it.

signal banner_resized(height_px: float)

var _ads: JavaScriptObject
## JS callbacks must stay referenced while the page may still call them.
var _on_resize: JavaScriptObject
var _on_rewarded_js: JavaScriptObject
var _on_interstitial_js: JavaScriptObject


func _ready() -> void:
	_ads = WebPlatform.api().ads
	_on_resize = JavaScriptBridge.create_callback(func(args: Array) -> void:
		_emit_fraction(float(args[0]) if args.size() > 0 else 0.0)
	)
	_ads.onBannerResize(_on_resize)


func show_banner() -> void:
	_emit_fraction(float(_ads.bannerShow()))


func hide_banner() -> void:
	_ads.bannerHide()


func _emit_fraction(f: float) -> void:
	banner_resized.emit(f * float(DisplayServer.window_get_size().y))


func rewarded_ready() -> bool:
	return bool(_ads.rewardedReady())


func show_rewarded(on_done: Callable) -> void:
	_on_rewarded_js = JavaScriptBridge.create_callback(func(args: Array) -> void:
		on_done.call(args.size() > 0 and bool(args[0]))
	)
	_ads.rewardedShow(_on_rewarded_js)


func interstitial_ready() -> bool:
	return WebPlatform.interstitials_allowed() and bool(_ads.interstitialReady())


func show_interstitial(on_done: Callable) -> void:
	_on_interstitial_js = JavaScriptBridge.create_callback(func(_args: Array) -> void:
		on_done.call()
	)
	_ads.interstitialShow(_on_interstitial_js)
