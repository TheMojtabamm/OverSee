# Google Play compliance checklist (VPN app + ads)

What the code already does, what you must do in the Play Console / AdMob, and what
can still get the app rejected. Policies change; re-read the linked policy pages
before every submission. This is an engineering checklist, not legal advice.

## 1. VpnService policy

| Requirement | Status |
|---|---|
| Use `VpnService` for the VPN function; declare it | ✅ `OverseaVpnService`, `BIND_VPN_SERVICE` |
| **Prominent in-app disclosure + consent before the VPN starts** | ✅ shown once before the system permission prompt (`connect_flow.dart`, strings `disclosure_*`). Keep the wording: what is routed, to whom, encryption, no logging/selling, ads |
| Encrypt traffic device → server | ✅ Xray protocols (TLS/Reality/SS/…). Plain `vmess`/`ss` without TLS is the config owner's choice; consider warning on non-TLS configs |
| Don't collect personal/sensitive data beyond need | ✅ no accounts, no analytics, no traffic logs |
| Don't redirect/manipulate traffic or ads of other apps (no ad injection, no replacing ad referrals) | ✅ the app never touches payload content |
| Store listing may not misrepresent (no "100% anonymous / unhackable", no unsupported claims) | ⚠️ you write the listing — avoid absolute claims |
| Always-on VPN support | ✅ `SUPPORTS_ALWAYS_ON`; with no config in memory the service holds a blocking interface instead of leaking |

## 2. Foreground service (special use)

`foregroundServiceType="specialUse"` + `PROPERTY_SPECIAL_USE_FGS_SUBTYPE=vpn`.
In Play Console → App content → *Foreground service permissions* you must declare the
`specialUse` type, describe it ("keeps the user's VPN tunnel running"), and attach a
short video showing the user starting and stopping the VPN and the persistent
notification. (If Google accepts `systemExempted` for your case, switch to it.)

## 3. Ads policy (AdMob interstitial after connect)

| Rule | How it is met |
|---|---|
| Consent where required (GDPR/UK/…) | ✅ Google **UMP** form before the SDK starts; no ad request unless `canRequestAds`; "Ad privacy options" entry in Settings when UMP requires it. **You must create the consent message in AdMob → Privacy & messaging** or the form never appears |
| Ads at natural breaks, not disruptive | ✅ only after the tunnel is *up*; never at launch, exit, disconnect or while connecting; re-checks the tunnel is still connected before showing |
| Frequency cap | ✅ ≥ 5 min between ads and **none on the first-ever connect** (`AdService.mayShow`, unit-tested) |
| No accidental clicks / misleading UI | ✅ stock AdMob interstitial; no custom close-button tricks |
| Content rating | ✅ `maxAdContentRating = PG` |
| Don't click your own ads / use test ads in dev | ✅ test unit unless `AD_INTERSTITIAL_ID` is injected at build time. Add your phone as an AdMob test device before QA |
| Third-party "owner" ads inside locked files | ✅ labelled **Sponsored**, text sanitised & capped, link restricted to https Telegram (`AdContent`), user must tap Continue. Still third-party content: consider a report/block option and AdMob-only monetisation if Google objects |
| App-ads.txt (if you publish a developer website) | ⚠️ optional but recommended for AdMob revenue |
| `AD_ID` permission | ✅ merged from the AdMob plugin. In **Play Console → App content → Advertising ID** declare that the app uses it for advertising |

## 4. Data safety form (Play Console)

Answer truthfully. With the current code:

* **Data collected/shared:** *Device or other IDs* (advertising ID, collected by the
  Google AdMob SDK) for *advertising*; shared with Google. *App activity / diagnostics:*
  collected by AdMob SDK (ad performance). Nothing else leaves the device.
* **Not collected by Oversea:** browsing history, traffic content, IPs, contacts, location.
* **Encrypted in transit:** yes (ads over HTTPS; tunnel encrypted by the protocol).
* **Deletion:** no account, no server-side user data.
* Provide the privacy policy URL (see `PRIVACY_POLICY.md`, host it on a public HTTPS page and pass it with `--dart-define=PRIVACY_POLICY_URL=…`).

## 5. Other requirements

* `targetSdk` is Flutter's current target (36). Play raises the minimum every year — keep Flutter updated.
* No `QUERY_ALL_PACKAGES`: the per-app picker uses a `<queries>` LAUNCHER intent.
* `allowBackup=false`, no cleartext traffic, FLAG_SECURE, R8 on.
* Content rating questionnaire: answer for a utility/VPN app; user-generated links (Telegram) via locked files count as "users can interact / share content" — answer honestly.
* **Region/legal:** VPN legality varies by country; Play may restrict availability. Don't market it as a way to break local law.
* Restricted content: owner messages in locked files can contain anything. Keep the sanitiser, and add a report mechanism before scaling.

## 6. Things I could not verify from here

* Play Console declarations and AdMob consent messages are account-side.
* Behaviour on a real device (VPN permission flow, notification, kill-switch hold,
  per-app routing) has **not** been tested — only compile/unit/Xray-loader checks.
