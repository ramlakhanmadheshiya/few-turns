# Few Turns on Google Play: what to put in every form

Follows `PLAY_PUBLISHING_GUIDE.md`, filled in for this exact build: Godot 4.7,
Google AdMob (Mobile Ads SDK + User Messaging Platform), Google Play Billing, and
a small share plugin (saves the share picture to the gallery). No analytics, no crash reporting, no accounts, no servers.

## Fixed facts (decide once, never change)

| Thing | Value |
|---|---|
| Package name | `com.theramlakhan.fewturns` (permanent after the first upload) |
| Upload key | the keystore in `~/.android-keys/` (password in `carom-release.txt`), also in the repo secrets `ANDROID_KEYSTORE_*`. Back it up off this Mac. |
| Version code | GitHub Actions run number (goes up on every push to `main`) |
| Version name | `1.0.<run number>` |
| Target SDK | 36 (`export_presets.cfg`), min SDK 24 |
| Play build | the **AAB** from the CI run: Actions > latest "Build & publish" > Artifacts > `few-turns-aab` |
| Support email | support@theramlakhan.com |
| Website | https://theramlakhan.com/few-turns/ |
| Privacy policy | https://theramlakhan.com/few-turns/privacy/ |
| Support page | https://theramlakhan.com/few-turns/help/ |

## Before the first upload (one-time setup)

1. **AdMob** (admob.google.com, same Google account): add the app (Android, "not listed yet"), create a **Banner**, a **Rewarded** and an **Interstitial** ad unit.
2. **GitHub secrets** (repo > Settings > Secrets and variables > Actions):
   - `ADMOB_APP_ID`: `ca-app-pub-…~…` (App settings in AdMob)
   - `ADMOB_BANNER_ID`, `ADMOB_REWARDED_ID`, `ADMOB_INTERSTITIAL_ID`: `ca-app-pub-…/…`
   - Until these exist, every build uses Google's test ads and CI prints a warning. **Never upload a build to Play that shows the warning.**
3. **app-ads.txt:** AdMob shows a line like `google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0`. It must live at `https://theramlakhan.com/app-ads.txt` (the root of the website you list on Play). Send the line to Claude, or add it to the `ramlakhanmadheshiya.github.io` repo as `app-ads.txt`.
4. **Optional, upload from CI:** create the service account (guide step 0.4), invite it in Play Console with release rights, and add its JSON key as the secret `PLAY_SERVICE_ACCOUNT_JSON`. From then on every push uploads the AAB to **Internal testing** automatically. The very first AAB must still be uploaded by hand.

## Create app (Home > Create app)

| Field | Answer |
|---|---|
| App name | Few Turns: Arrow Puzzle |
| Default language | English (United States) |
| App or game | Game |
| Free or paid | Free |
| Declarations | Tick all, accept Play App Signing |

## App content (Policy and programs > App content)

| Form | Answer |
|---|---|
| Privacy policy | https://theramlakhan.com/few-turns/privacy/ |
| App access | All functionality is available without special access |
| Ads | **Yes**, the app contains ads |
| Content rating | See below |
| Target audience | **13–15, 16–17, 18 and over**. Not designed for children. "Could your store listing unintentionally appeal to children?" No: an abstract logic puzzle with no characters or child-directed themes. |
| News app | No |
| COVID-19 | No |
| Government app | No |
| Financial features | None of these |
| Health | None |
| Advertising ID | **Yes**. Purposes: Advertising or marketing, Analytics, Fraud prevention, security and compliance (AdMob uses it). |
| Data safety | See below |

### Content rating (IARC questionnaire)

- Category: **Game** (puzzle)
- Violence, blood, fear, sexuality, nudity, crude humour, language, drugs, alcohol, tobacco: **No** to all (only abstract shapes)
- Gambling or simulated gambling: **No** (rewarded ads give hints, keys or a trial; nothing random)
- Users can interact or exchange content in the app: **No** (sharing goes out through the phone's own share sheet; there is no in-app chat or user content)
- Shares the user's location: **No**
- Lets users buy digital goods: **Yes**
- Unrestricted internet access: **No**
- Expected result: Everyone / PEGI 3 / IARC 3+, with "Contains ads" and "In-app purchases"

### Data safety

Overview questions:
- Does the app collect or share any of the required user data types? **Yes**
- Is all user data encrypted in transit? **Yes**
- Do you provide a way for users to request that their data is deleted? **No** (the developer stores no user data; progress lives only on the device and is deleted with the app. Ad data is controlled through the user's Google account and advertising ID settings.)

Data types (each: **required**, not optional, unless noted):

| Data type | Collected | Shared | Purposes | Comes from |
|---|---|---|---|---|
| Location > Approximate location | Yes | Yes | Advertising or marketing, Analytics, Fraud prevention, security and compliance | AdMob |
| App activity > App interactions | Yes | Yes | Advertising or marketing, Analytics, Fraud prevention, security and compliance | AdMob |
| App info and performance > Diagnostics | Yes | Yes | Advertising or marketing, Analytics, Fraud prevention, security and compliance | AdMob |
| Device or other IDs | Yes | Yes | Advertising or marketing, Analytics, Fraud prevention, security and compliance | AdMob (advertising ID) |
| Financial info > Purchase history | Yes | No | App functionality | Google Play Billing |

Not collected: name, email, contacts, photos or videos (the share picture is saved by the user to their own gallery; nothing is uploaded), files, messages, audio, health, precise location, web history, search history.

Re-check AdMob's own Data safety guidance (developers.google.com/admob/android/privacy/play-data-disclosure) before submitting, and update this table and the privacy policy whenever an SDK is added or changed.

## Store listing (Grow users > Store presence > Main store listing)

Everything is in `store/listing.md` (text, checked by `python3 store/check_listing.py`) and:

| Asset | File |
|---|---|
| App icon 512 × 512 | `store/icon_512.png` |
| Feature graphic 1024 × 500 | `store/feature_graphic.png` |
| Phone screenshots 1080 × 1920 | `store/screenshots/01_lay.png` … `08_home.png` |

Store settings: category **Games > Puzzle**, tags from `listing.md`, email support@theramlakhan.com, website https://theramlakhan.com/few-turns/. No phone number needed.

Re-render the art any time: `godot --fixed-fps 60 --disable-vsync --always-on-top --path . res://tests/capture.tscn -- build/store/raw --store-raw`, then `.venv/bin/python -I tools/store_art.py install C` and `godot --headless --path . -s res://tools/render_icon.gd -- store/icon_512.png`.

## In-app products (Monetize with Play > Products, after the first AAB is on a track)

204 products, prices in rupees (Play converts the rest):

| Kind | IDs | Price |
|---|---|---|
| One-time packs | `complete_pack`, `supporter_pack`, `orb_pack`, `theme_pack` | ₹449, ₹249, ₹149, ₹149 |
| Level keys (consumed in the app) | `keys_1` … `keys_10` | ₹30 each, 10% off for 5 or more |
| Tips (consumed in the app) | `tip_10` … `tip_10000` (steps of 10 to 1,000, then 100) | the amount in the ID |

Full list: `python3 store/play_products.py list` (also `store/products.csv`).
Create them all at once with the service account: `python3 -m pip install google-auth requests` then `python3 store/play_products.py create path/to/key.json`. It skips any that already exist.
Then add your own Gmail under Settings > License testing so you can buy with test cards.

## Testing

1. **Internal testing:** upload the AAB from the CI artifact by hand, add yourself, install from the opt-in link, play on a real phone: the ads (real units only show test ads to you until AdMob approves the app), a purchase with a test card, Restore, Save (the picture lands in Pictures › Few Turns), and Share.
2. **Closed testing** (required for new personal accounts): at least **12 testers opted in for 14 days in a row**; invite 15–20. Keep notes of feedback and fixes for the production application.

   Message to send testers:

   > Hi! I've made a calm puzzle game called Few Turns and need testers on Google Play for 14 days. Join with the Gmail you use on your Android phone: [opt-in link]. Install it, play a few rooms whenever you like, and keep it installed for two weeks. Tell me anything confusing, too hard, or broken: support@theramlakhan.com. Thank you!

## Apply for production (after the 14 days)

Draft answers (edit with what really happened):

- **About the test:** Testers were friends, family and fellow players recruited by message. They played on their own Android phones over 14 days and reported by email and chat. Feedback covered level difficulty, the moving-platform chapter's speed, sound levels and sharing; fixed in builds 1.0.x (list the real changes).
- **About the app:** A calm, ad-light arrow puzzle for teens and adults who like short logic puzzles. 360 rooms in 9 chapters, each teaching one new idea; a solver proves every room needs exactly the turns it gives. Expected installs in the first year: 1,000–10,000.
- **About readiness:** All tester issues are fixed, the app has run on several phones without crashes, purchases and ads are tested, and the privacy policy and Data safety form match the SDKs in the build.

## After launch

1. AdMob > Apps > link the Play listing > verify (needs `app-ads.txt`).
2. Watch Android vitals, reviews, and AdMob's Policy center.
3. Every update: push to `main` (the version code goes up by itself), check the internal track build, then promote it to production with 2–5 short release notes.
