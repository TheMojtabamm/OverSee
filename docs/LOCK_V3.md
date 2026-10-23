# Oversea lock format v3 (`.ovsea`)

Offline, no server. Implemented in `lib/domain/locked_config_codec.dart`; tests in
`test/locked_config_codec_test.dart`. Supersedes the v1 Dart codec and the
server-gated "v2" Go design (the Go `/v1/lock/*` endpoints are no longer used by
the app).

## File layout

`base64url( header ‖ nonce ‖ ciphertext ‖ tag )`

| Field | Size | Notes |
|---|---|---|
| magic | 4 | `OVS3` — the only cleartext marker |
| version | 1 | `3` |
| key generation | 1 | selects which secret generation made the file |
| salt | 16 | random per file |
| nonce | 12 | random per file (AES-GCM) |
| ciphertext | n | JSON `{"c": config, "a": ad?, "t": telegram?, "g": gen}` |
| tag | 16 | AES-GCM tag |

`header` = magic ‖ version ‖ generation ‖ salt is passed as AEAD associated data,
so flipping any header bit fails authentication.

**Nothing else is cleartext**: no epoch, no host, no title, no ad, no link.

## Key derivation

```
secret   = XOR-mask-rejoin(LOCK_P1 ‖ LOCK_P2 ‖ LOCK_P3 ‖ LOCK_P4)   // CI secrets, not in repo
k0       = HMAC-SHA256(secret ‖ "ovsea|v3|gen<N>", salt ‖ "ovsea-lock-v3")
k_i+1    = HMAC-SHA256(secret ‖ "ovsea|v3|gen<N>", k_i)               // 4096 rounds
key      = k_4096   (AES-256-GCM)
```

* The four parts are separate `--dart-define`s so the full secret is never one
  contiguous string in the binary, and a source checkout contains none of it.
* Per-file salt ⇒ per-file key; stretching makes bulk offline work per file.

## Rotation

Each app release should (a) change `LOCK_P1..P4` and (b) bump
`LockedConfigCodec.keyGeneration`. A bot built from an old APK then cannot open
files made by new builds, and must re-extract the secret from every release.

## App-side rules

* Imported locked configs are stored with `locked=true`: server address hidden,
  no Copy, no QR, no plain Share. They can only be connected.
* Import errors are deliberately uninformative.
* Exports are file-only; the blob is never put in the share text.
* Screenshots / recents thumbnails are blocked (`FLAG_SECURE`).

## Known limitation (read this)

The app opens files offline, so everything needed to open them is inside the
APK. A determined reverse engineer can recover the secret and write a decoder.
v3 raises the cost and makes a stolen secret expire with each release; it does
not make extraction impossible.

## Planned next (not yet implemented)

* **Ed25519 signature** over the header+ciphertext with the owner's private key,
  verified in-app with an embedded public key. Without it, anyone who recovers
  the secret can also *create* valid files (e.g. re-lock a stolen config under
  their own ad/channel). With it, a recovered secret only allows reading.
* Move the open/derive path into native code (C++/JNI) with per-build generated
  constants.
* Per-blob credentials with expiry on the owner's Xray panel (leak = revoke).
