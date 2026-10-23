import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:share_plus/share_plus.dart";

import "../../app.dart";
import "../../core/log.dart";
import "../../core/strings.dart";
import "../../domain/locked_config_codec.dart";
import "../../domain/vpn_config.dart";

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
        final blob = await LockedConfigCodec.encode(
          c.raw,
          adText: _adCtrl.text.trim(),
          telegramUrl: _tgCtrl.text.trim(),
        );
        final name = "oversea_${DateTime.now().millisecondsSinceEpoch}.ovsea";
        // File only — no plaintext, and no blob in the message text.
        await Share.shareXFiles([
          XFile.fromData(
            Uint8List.fromList(utf8.encode(blob)),
            name: name,
            mimeType: "application/octet-stream",
          )
        ]);
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(c.name.isNotEmpty ? c.name : (c.host ?? "Config"),
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _lock,
              onChanged: (v) => setState(() {
                _lock = v ?? false;
                if (_lock)
                  _showQr = false; // a QR would expose the plain config
              }),
              title: Text(s.t("lock_title")),
              subtitle: Text(s.t("lock_sub")),
              secondary: const Icon(Icons.lock, color: accent),
            ),
            if (_lock) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _adCtrl,
                decoration: InputDecoration(
                  labelText: s.t("ad_text"),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tgCtrl,
                decoration: InputDecoration(
                  labelText: s.t("tg_url"),
                  hintText: "https://t.me/yourchannel",
                  border: const OutlineInputBorder(),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c.raw));
                        _snack(s.t("copied"));
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(s.t("copy")),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _showQr = !_showQr),
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: Text(_showQr ? s.t("hide_qr") : s.t("qr")),
                    ),
                  ),
                ],
              ),
              if (_showQr)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(data: c.raw, size: 240),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_lock ? Icons.lock : Icons.share),
              label: Text(_lock ? s.t("lock_share") : s.t("share")),
            ),
          ],
        ),
      ),
    );
  }
}
