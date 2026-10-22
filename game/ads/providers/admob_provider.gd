extends Node
## Google AdMob through the Poing AdMob plugin (Android only).
## Flow: consent (UMP, needed for EU/UK) -> initialise -> preload a rewarded ad;
## the bottom banner is an anchored adaptive banner; an interstitial is preloaded
## for the between-levels break (AdManager decides when).

signal banner_resized(height_px: float)

## Ad unit IDs come from Project Settings (few_turns/ads/*), which CI fills in
## from the repository secrets ADMOB_BANNER_ID, ADMOB_REWARDED_ID and
## ADMOB_INTERSTITIAL_ID (and the App ID,
## admob/general/android/app_id, from ADMOB_APP_ID). Without them, Google's public
## TEST units are used, so development builds never show real ads.
const TEST_BANNER_ID: String = "ca-app-pub-3940256099942544/9214589741"
const TEST_REWARDED_ID: String = "ca-app-pub-3940256099942544/5224354917"
const TEST_INTERSTITIAL_ID: String = "ca-app-pub-3940256099942544/1033173712"
var BANNER_ID: String = _unit("android_banner_id", TEST_BANNER_ID)
var REWARDED_ID: String = _unit("android_rewarded_id", TEST_REWARDED_ID)
var INTERSTITIAL_ID: String = _unit("android_interstitial_id", TEST_INTERSTITIAL_ID)


static func _unit(key: String, fallback: String) -> String:
	var v: String = str(ProjectSettings.get_setting("few_turns/ads/" + key, ""))
	return v if not v.strip_edges().is_empty() else fallback

var _ready_to_load: bool = false
var _banner_wanted: bool = false
var _ad_view: AdView
var _rewarded: RewardedAd
var _rewarded_loader: RewardedAdLoader
var _on_rewarded: Callable
var _earned: bool = false
var _interstitial: InterstitialAd
var _interstitial_loader: InterstitialAdLoader
var _on_interstitial: Callable


static func is_supported() -> bool:
	return Engine.has_singleton("PoingGodotAdMob")


func _ready() -> void:
	_rewarded_loader = RewardedAdLoader.new()
	_interstitial_loader = InterstitialAdLoader.new()
	var params: ConsentRequestParameters = ConsentRequestParameters.new()
	UserMessagingPlatform.consent_information.update(params, _on_consent_updated, func(_e: FormError) -> void: _init_ads())


func _on_consent_updated() -> void:
	var ci: ConsentInformation = UserMessagingPlatform.consent_information
	if ci.get_is_consent_form_available() and ci.get_consent_status() == ConsentInformation.ConsentStatus.REQUIRED:
		UserMessagingPlatform.load_consent_form(
			func(form: ConsentForm) -> void: form.show(func(_e: FormError) -> void: _init_ads()),
			func(_e: FormError) -> void: _init_ads())
	else:
		_init_ads()


## True when the player must be offered "Privacy options" (EU consent) in settings.
func privacy_options_required() -> bool:
	return UserMessagingPlatform.consent_information.get_privacy_options_requirement_status() \
		== ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options() -> void:
	UserMessagingPlatform.show_privacy_options_form(func(_e: FormError) -> void: pass)


func _init_ads() -> void:
	if _ready_to_load:
		return
	var cfg: RequestConfiguration = RequestConfiguration.new()
	cfg.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_G
	MobileAds.set_request_configuration(cfg)
	var listener: OnInitializationCompleteListener = OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_s: InitializationStatus) -> void:
		_ready_to_load = true
		_load_rewarded()
		_load_interstitial()
		if _banner_wanted:
			show_banner()
	MobileAds.initialize(listener)


# --- Banner ---------------------------------------------------------------------

func show_banner() -> void:
	_banner_wanted = true
	if not _ready_to_load:
		return
	if _ad_view != null:
		_ad_view.show()
		banner_resized.emit(float(_ad_view.get_height_in_pixels()))
		return
	var size: AdSize = AdSize.get_current_orientation_anchored_adaptive_banner_ad_size(AdSize.FULL_WIDTH)
	_ad_view = AdView.new(BANNER_ID, size, AdPosition.BOTTOM)
	_ad_view.ad_listener.on_ad_loaded = func() -> void:
		if _banner_wanted:
			banner_resized.emit(float(_ad_view.get_height_in_pixels()))
	_ad_view.ad_listener.on_ad_failed_to_load = func(e: LoadAdError) -> void:
		push_warning("Banner failed: %d %s" % [e.code, e.message])
		banner_resized.emit(0.0)
	_ad_view.load_ad(AdRequest.new())


func hide_banner() -> void:
	_banner_wanted = false
	if _ad_view != null:
		_ad_view.destroy()
		_ad_view = null
	banner_resized.emit(0.0)


# --- Rewarded ------------------------------------------------------------------------

func rewarded_ready() -> bool:
	return _rewarded != null


func show_rewarded(on_done: Callable) -> void:
	if _rewarded == null:
		on_done.call(false)
		return
	_on_rewarded = on_done
	_earned = false
	var rl: OnUserEarnedRewardListener = OnUserEarnedRewardListener.new()
	rl.on_user_earned_reward = func(_item: RewardedItem) -> void: _earned = true
	_rewarded.show(rl)


func _load_rewarded() -> void:
	var cb: RewardedAdLoadCallback = RewardedAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: RewardedAd) -> void:
		_rewarded = ad
		var fs: FullScreenContentCallback = FullScreenContentCallback.new()
		fs.on_ad_dismissed_full_screen_content = func() -> void: _rewarded_done(false)
		fs.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void: _rewarded_done(true)
		_rewarded.full_screen_content_callback = fs
	cb.on_ad_failed_to_load = func(e: LoadAdError) -> void: push_warning("Rewarded failed: " + e.message)
	_rewarded_loader.load(REWARDED_ID, AdRequest.new(), cb)


## The reward is granted after the ad closes if it was earned — or if the ad
## failed to show, so a broken ad never leaves the player empty-handed.
func _rewarded_done(failed: bool) -> void:
	if _rewarded != null:
		_rewarded.destroy()
	_rewarded = null
	_load_rewarded()
	if _on_rewarded.is_valid():
		_on_rewarded.call(_earned or failed)
	_on_rewarded = Callable()


# --- Interstitial --------------------------------------------------------------------

func interstitial_ready() -> bool:
	return _interstitial != null


func show_interstitial(on_done: Callable) -> void:
	if _interstitial == null:
		on_done.call()
		return
	_on_interstitial = on_done
	_interstitial.show()


func _load_interstitial() -> void:
	var cb: InterstitialAdLoadCallback = InterstitialAdLoadCallback.new()
	cb.on_ad_loaded = func(ad: InterstitialAd) -> void:
		_interstitial = ad
		var fs: FullScreenContentCallback = FullScreenContentCallback.new()
		fs.on_ad_dismissed_full_screen_content = _interstitial_done
		fs.on_ad_failed_to_show_full_screen_content = func(_e: AdError) -> void: _interstitial_done()
		_interstitial.full_screen_content_callback = fs
	cb.on_ad_failed_to_load = func(e: LoadAdError) -> void: push_warning("Interstitial failed: " + e.message)
	_interstitial_loader.load(INTERSTITIAL_ID, AdRequest.new(), cb)


func _interstitial_done() -> void:
	if _interstitial != null:
		_interstitial.destroy()
	_interstitial = null
	_load_interstitial()
	if _on_interstitial.is_valid():
		_on_interstitial.call()
	_on_interstitial = Callable()
