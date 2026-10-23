# The gate: making a decoded config worthless outside the app

## What it defends against
A locked file can always be opened by the app, so someone with the app (or a bot
built on it) can recover the plain `vless://…`. The gate makes that link **useless**:
the owner's server only accepts connections that carry a token only the Oversea app
can compute, for a lock the owner created, from a file the owner signed.

```
token = <codeId>.<day>.hex( HMAC(appKey, "ovsea-gate-v2|" + lockCode + "|" + creatorFp + "|" + day) )
```

| Secret | Where it lives | What it proves |
|---|---|---|
| `appKey` | built into the app (CI secret `GATE_KEY`), on the server as `GATE_KEYS` | the client is the Oversea app |
| `lockCode` | random 128-bit per lock, inside the (signed, encrypted) file; the owner's allow-list | this exact lock was issued by the server's owner |
| `creatorFp` | from the file's **verified** Ed25519 signature; the owner's allow-list pins it | the file was signed by the owner |

One MAC covers all three, so nothing can be mixed and matched.

## The thief scenario
1. Thief decodes the owner's file (needs the app secret) → gets the link, `lockCode`, ads.
2. Thief pastes the link into another app → **refused**: no token at all.
3. Thief re-locks the config in the Oversea app with their own ad → the app signs with
   the **thief's** identity, so it computes the token with `creatorFp = thief`. The
   owner's allow-list line says `creatorFp = owner` → MAC mismatch → **refused**.
   (`server/internal/gate` `TestValid/"re-locked under another creator"`, and
   `tool/e2e_gate.sh` with real Xray.)
4. Thief patches the app (or writes a client) to claim the owner's fingerprint → this
   needs the `appKey` and a modified client; followers would have to install that
   client, not the Play build. This is the residual risk, and the reason `appKey` is
   rotated per release (`GATE_KEYS=new,old`).

**Revoke:** delete the lock's line from `allow.txt`; the gate reloads within ~3 s and
every copy of that lock stops working. Issue a new file (new code) to real followers.

## Owner workflow
1. App → config → Share → **Lock** → tick *Server gate* → *Lock & share file*.
2. The app shows one line `<code> <fingerprint> <note>` (also under Settings → Gate
   allow-list). Add it to `allow.txt` on the server.
3. Run the gate in front of Xray (below). Hand out the `.ovsea` file.

## Server setup — the `oversee` tool

One command installs a single binary (checksum-verified, no dependencies) and a
systemd unit:

```
curl -fsSL https://github.com/themojtabamm/OverSee/releases/latest/download/install.sh | sudo bash
```

Then `sudo oversee` opens the manager (TUI):

| Tab | What it does |
|---|---|
| **Status** | service state, counts, and what's still missing. `s` start · `x` stop · `R` restart · `e` enable at boot |
| **Locks** | list the locks you allowed. `a` paste the line the app shows → live in ~3 s · `d` revoke (asks first) |
| **Keys** | the app key(s) your Oversea build was made with (`GATE_KEY`). `n` add · `g` generate · `d` remove. Newest first; keep the previous one until old builds age out. No restart needed |
| **Setup** | set your domain / Xray port; shows a ready-made Xray WebSocket inbound and the matching client link |
| **Logs** | recent gate logs |

Scriptable too: `oversee list`, `oversee add "<line>"`, `oversee revoke <id>`,
`oversee keys`, `oversee key add <key>`, `oversee status`.

Xray listens on `127.0.0.1:10000` with a **WebSocket or HTTPUpgrade** inbound and
`security: none` (the Setup tab prints one); the gate owns `:80/:443` and gets a
Let's Encrypt certificate for your domain automatically. Files live in `/etc/oversea`
(`allow.txt`, `keys.txt` 0600, `gate.conf`). A malformed edit to a file is ignored
(the previous list stays active) and logged. With no app key the gate refuses
everyone (fail closed). Uninstall: `… | sudo bash -s -- --uninstall`.

The release is built by `.github/workflows/server-release.yml` when you push a tag
like `server-v1.0.0` (the repo must be public for the one-liner to download it).

## Limits
* WebSocket / HTTPUpgrade only (one check per connection). Reality+TCP and XHTTP
  can't carry the header; the app refuses to lock them as gated.
* Cost: one HMAC (~2 µs) per new connection, plus the proxy hop. Bandwidth, not the
  check, dominates. Measure with your real traffic.
* Not unbreakable: someone who extracts `appKey` **and** builds a client can mint
  tokens. Rotate `appKey` each release; revoke leaked locks.
* A public free config shared with millions can't be hidden from anyone who wants
  it; the gate stops it being *reused outside the app or re-branded under another
  creator*, nothing more.
* Xray's `freedom` outbound blocks private targets by default; keep it that way in
  production (the e2e test relaxes it only for its local origin).
