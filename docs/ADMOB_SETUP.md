# AdMob setup: what the owner provides so ad revenue reaches the owner's account

Revenue goes to whichever AdMob account owns the IDs compiled into the release. The app
makes no revenue split; only the app owner earns. Creators who lock configs get no ad money.

## You provide (all from https://admob.google.com, under your own account)
1. **Add the app** → Android → AdMob gives an **App ID** `ca-app-pub-XXXX~YYYY`.
2. **Create two ad units** in that app:
   - Interstitial → `ca-app-pub-XXXX/ZZZZ`
   - Banner → `ca-app-pub-XXXX/WWWW`
3. **Privacy & messaging → GDPR message**: create and publish one (the app shows it via UMP).
4. **Payments**: tax and payment info so AdMob can pay you.
5. Link the app to its **Play Store listing** after the first Play upload (needed for serving).
6. **app-ads.txt** on your developer website (the one in your Play listing), with the line AdMob shows.
7. Play Console: **App content → Advertising ID** = Yes (ads), **Data safety** (see PLAY_COMPLIANCE.md),
   and a public **privacy policy URL** (draft in PRIVACY_POLICY.md).

## GitHub repository secrets to add
| Secret | Value |
|---|---|
| `ADMOB_APP_ID` | the App ID from step 1 |
| `AD_INTERSTITIAL_ID` | interstitial unit ID |
| `AD_BANNER_ID` | banner unit ID |

The release workflow now **fails** if any of these is missing or one of Google's test IDs,
so a release cannot ship with test ads by accident. The existing signing, `LOCK_P1..P4`,
`GATE_KEY` secrets are also needed (see GATE.md / release.yml).

## Before real users
- Never tap your own live ads (account suspension). Add your phone as an AdMob **test device**.
- New apps can show few or no ads for a day or two until AdMob approves the app.
