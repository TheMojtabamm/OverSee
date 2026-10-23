# Threat model

Asset: a free Xray config distributed as a locked file, plus the owner's ad and
channel link embedded in it.

| # | Attacker | Goal | Today | Planned |
|---|----------|------|-------|---------|
| 1 | Casual user | Copy the config out of the app or a file | **Blocked**: locked configs have no Copy/QR/plain Share, server hidden, no cleartext in file, FLAG_SECURE | — |
| 2 | Channel that re-posts the file | Pass the same file off as theirs | Not preventable (the file is valid for everyone). The embedded ad/channel still shows the original owner's link | Short expiry; owner rotates files |
| 3 | Bot builder (automated) | "Upload file → get config" Telegram bot | **Raised cost**: secret is split, not in the repo, per-file key stretch, rotates per release. Still recoverable by someone who reverse-engineers an APK | Native opener, per-build generated constants, commercial protector |
| 4 | Attacker with recovered secret | Re-brand a stolen config under their own ad/channel | **Possible, but visible**: files are Ed25519-signed; the copy shows the copier's fingerprint, not the owner's. Not preventable while any user may lock | Owner-only locking tool (key never in the public app) if you need prevention |
| 5 | Modified/repackaged app | Remove ad, expose config | Not prevented | Signature check at runtime, Play Integrity (online) |
| 6 | Root + Frida on a real device | Read config from memory | Not preventable on-device | Make leaked config short-lived/revocable on the Xray panel |
| 7 | Local file/backup reader | Read stored configs | **Blocked**: Keystore-backed secure storage, `allowBackup=false`, legacy plaintext migrated and wiped | — |
| 8 | Network attacker | MITM of future API calls | Cert pinning (SPKI) client ready; fails closed in prod without pins | Enable when an API exists |
| 9 | Log scraper | Config from logcat | Release logs off, config URIs redacted in debug, R8 strips `android.util.Log` | — |

Principle: the app cannot keep a secret from its own device owner. Defence is
(a) make bulk automation expensive and short-lived, (b) make a leaked config
low-value (expiry, revocation), (c) never trust a client-side check for a server
decision.
