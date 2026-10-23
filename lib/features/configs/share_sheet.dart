import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:path_provider/path_provider.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:share_plus/share_plus.dart";

import "../../core/log.dart";
import "../../data/identity_store.dart";
import "../../core/strings.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";
import "../../domain/ad_content.dart";
import "../../domain/locked_config_codec.dart";
import "../../domain/gate_token.dart";
import "../../domain/vpn_config.dart";
import "../../domain/xray_config_builder.dart";
import "gate_line_card.dart";

Future<void> showShareSheet(BuildContext context, VpnConfig c) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ShareSheet(config: c),
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  final VpnConfig config;
  const _ShareSheet({required this.config});
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _lock = false;
  bool _showQr = false;
  bool _busy = false;

  /// Locking with the server gate is the default whenever it is possible: without it a
  /// decoded file's config works in any app.
  late bool _gate =
      GateToken.available && XrayConfigBuilder.supportsGate(widget.config.raw);
  Duration? _ttl = const Duration(days: 7);
  final _adCtrl = TextEditingController();
  final _tgCtrl = TextEditingController();

  @override
  void dispose() {
    _adCtrl.dispose();
    _tgCtrl.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _export() async {
    final c = widget.config;
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      if (_lock) {
        if (!LockedConfigCodec.hasKey) {
          _snack(s.t("no_key"));
          return;
        }
        if (_gate && !XrayConfigBuilder.supportsGate(c.raw)) {
          _snack(s.t("gate_unsupported"));
          return;
        }
        final tgInput = _tgCtrl.text.trim();
        final tg = AdContent.channelUrl(tgInput);
        if (tgInput.isNotEmpty && tg == null) {
          _snack(s.t("invalid_tg"));
          return;
        }
        final store = IdentityStore();
        final identity = await store.load();
        // One fresh random code per lock; only this device's owner ever sees it.
        final gateCode = _gate ? GateToken.newCode() : null;
        final blob = await LockedConfigCodec.encode(
          c.raw,
          adText: AdContent.text(_adCtrl.text),
          telegramUrl: tg,
          signer: identity,
          gateCode: gateCode,
          expiresAt: _ttl == null ? null : DateTime.now().add(_ttl!),
        );
        String? line;
        if (gateCode != null) {
          line = GateToken.allowListLine(gateCode, identity.fingerprint,
              note: c.name.isNotEmpty
                  ? c.name.replaceAll(RegExp(r"\s+"), "_")
                  : "");
          await store.addGateLine(line);
          if (mounted) await showGateLineDialog(context, line);
        }
        // A real file with the right name: shareXFiles(XFile.fromData) ignores the name on
        // Android and the receiver saw "….bin".
        final dir = await getTemporaryDirectory();
        for (final f in dir.listSync().whereType<File>()) {
          if (f.path.endsWith(".ovsea")) f.deleteSync(); // earlier exports
        }
        final file = File(
            "${dir.path}/oversea_${DateTime.now().millisecondsSinceEpoch}.ovsea");
        await file.writeAsString(blob, flush: true);
        // File only: no plaintext, and no blob in the message text.
        await Share.shareXFiles(
            [XFile(file.path, mimeType: "application/octet-stream")]);
      } else {
        await Share.share(c.raw);
      }
    } catch (e) {
      Log.d("export failed: $e");
      _snack("Export failed");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = widget.config;
    final col = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconTile(_lock ? Icons.lock_rounded : Icons.ios_share_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t("share"),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      Text(c.name.isNotEmpty ? c.name : (c.host ?? ""),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: col.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Mode switch: plain share vs. protected file
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: Text(s.t("share_plain"))),
                ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.lock_rounded, size: 18),
                    label: Text(s.t("share_locked"))),
              ],
              selected: {_lock},
              onSelectionChanged: (v) => setState(() {
                _lock = v.first;
                if (_lock) {
                  _showQr = false; // a QR would expose the plain config
                }
              }),
            ),
            const SizedBox(height: 16),
            if (_lock) ...[
              Text(s.t("lock_sub"),
                  style: TextStyle(color: col.muted, height: 1.5)),
              const SizedBox(height: 14),
              TextField(
                controller: _adCtrl,
                maxLength: 200,
                decoration:
                    InputDecoration(labelText: s.t("ad_text"), counterText: ""),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tgCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                    labelText: s.t("tg_url"),
                    hintText: "https://t.me/yourchannel"),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<Duration?>(
                initialValue: _ttl,
                decoration: InputDecoration(labelText: s.t("expires")),
                borderRadius: BorderRadius.circular(14),
                items: [
                  DropdownMenuItem(
                      value: const Duration(hours: 24),
                      child: Text(s.t("exp_1d"))),
                  DropdownMenuItem(
                      value: const Duration(days: 7),
                      child: Text(s.t("exp_7d"))),
                  DropdownMenuItem(
                      value: const Duration(days: 30),
                      child: Text(s.t("exp_30d"))),
                  DropdownMenuItem(value: null, child: Text(s.t("exp_never"))),
                ],
                onChanged: (v) => setState(() => _ttl = v),
              ),
              const SizedBox(height: 6),
              if (!GateToken.available)
                _Warn(text: s.t("gate_unavailable_notice"))
              else if (!XrayConfigBuilder.supportsGate(c.raw))
                _Warn(text: s.t("gate_unsupported_notice"))
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _gate,
                  onChanged: (v) => setState(() => _gate = v),
                  title: Text(s.t("gate_title"),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(s.t("gate_hint"),
                      style: TextStyle(
                          fontSize: 12.5, color: col.muted, height: 1.4)),
                ),
                if (!_gate) _Warn(text: s.t("gate_off_warning")),
              ],
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c.raw));
                        _snack(s.t("copied"));
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(s.t("copy")),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _showQr = !_showQr),
                      icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: Text(_showQr ? s.t("hide_qr") : s.t("qr")),
                    ),
                  ),
                ],
              ),
              if (_showQr)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(data: c.raw, size: 220),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_lock ? Icons.lock_rounded : Icons.ios_share_rounded),
              label: Text(_lock ? s.t("lock_share") : s.t("share")),
            ),
          ],
        ),
      ),
    );
  }
}

/// A caution box: the locked file will hide the config inside the app, but a decoded
/// config would then work anywhere.
class _Warn extends StatelessWidget {
  final String text;
  const _Warn({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: c.warn),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style:
                      TextStyle(fontSize: 12.5, height: 1.45, color: c.warn))),
        ],
      ),
    );
  }
}
