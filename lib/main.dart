import "dart:async";
import "dart:convert";
import "dart:typed_data";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:qr_flutter/qr_flutter.dart";
import "package:share_plus/share_plus.dart";
import "package:url_launcher/url_launcher.dart";

import "models/vpn_config.dart";
import "services/ad_service.dart";
import "services/config_parser.dart";
import "services/config_store.dart";
import "services/locked_config_codec.dart";

const _accent = Color(0xFF38E1D4);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ads must never block startup; failures are swallowed.
  unawaited(AdService.init().catchError((_) {}));
  runApp(const OverseaApp());
}

class OverseaApp extends StatelessWidget {
  const OverseaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Oversea",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: _accent,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  ROOT SHELL — Configs / Add
// ══════════════════════════════════════════════════════════════════════
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;
  // Bumped after an add so the list reloads when we switch back to it.
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ConfigsScreen(key: ValueKey(_reload)),
          AddScreen(onAdded: () => setState(() {
                _reload++;
                _tab = 0;
              })),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.vpn_lock), label: "Configs"),
          NavigationDestination(icon: Icon(Icons.add_circle_outline), label: "Add"),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  CONFIGS — list, connect, share
// ══════════════════════════════════════════════════════════════════════
class ConfigsScreen extends StatefulWidget {
  const ConfigsScreen({super.key});
  @override
  State<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends State<ConfigsScreen> {
  final ConfigStore _store = ConfigStore();
  List<VpnConfig> _configs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final configs = await _store.load();
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _loading = false;
    });
  }

  /// Tap a config: for a locked config that carries the owner's ad / channel,
  /// show it first; then connect. After a successful connect an ad is shown.
  Future<void> _connect(VpnConfig c) async {
    final hasAd = c.adText != null && c.adText!.isNotEmpty;
    final hasTg = c.telegramUrl != null && c.telegramUrl!.isNotEmpty;

    if (c.locked && (hasAd || hasTg)) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.campaign, size: 48, color: _accent),
          title: Text(c.name.isNotEmpty ? c.name : "Channel"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasAd)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(c.adText!, textAlign: TextAlign.center),
                ),
              if (hasTg)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openUrl(c.telegramUrl!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text("Open Channel"),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Continue"),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    // TODO(engine): start the Xray tunnel here and only continue once it is up.
    // Until the engine is wired, this stands in for "connected" so the
    // post-connect ad flow can be exercised end-to-end.
    final connected = await _startTunnel(c);
    if (!mounted) return;
    if (connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connected — ${c.name.isNotEmpty ? c.name : c.host ?? "config"}")),
      );
      AdService.showAfterConnect();
    }
  }

  Future<bool> _startTunnel(VpnConfig c) async => true;

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Configs (${_configs.length})"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.vpn_lock, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text("No configs yet.",
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                        SizedBox(height: 8),
                        Text("Open the Add tab to paste a config or import a locked file.",
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _configs.length,
                  itemBuilder: (_, i) {
                    final c = _configs[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: Icon(c.locked ? Icons.lock : Icons.shield, color: _accent),
                        title: Text(c.name.isNotEmpty ? c.name : (c.host ?? "?")),
                        // Locked configs never reveal their server address.
                        subtitle: Text(c.locked
                            ? "${c.protocol.label} • Locked"
                            : "${c.protocol.label} • ${c.host ?? "?"}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Locked configs cannot be re-shared: that would
                            // allow re-locking them under someone else's name.
                            if (!c.locked)
                              IconButton(
                                icon: const Icon(Icons.share, size: 20),
                                onPressed: () => showShareSheet(context, c),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                              onPressed: () async {
                                await _store.remove(c.id);
                                _load();
                              },
                            ),
                          ],
                        ),
                        onTap: () => _connect(c),
                      ),
                    );
                  },
                ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  SHARE SHEET — QR, copy, or lock → .ovsea file
// ══════════════════════════════════════════════════════════════════════
Future<void> showShareSheet(BuildContext context, VpnConfig c) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
    setState(() => _busy = true);
    try {
      if (_lock) {
        if (!LockedConfigCodec.hasKey) {
          _snack("This build has no lock key — locking is unavailable.");
          return;
        }
        final blob = await LockedConfigCodec.encode(
          c.raw,
          adText: _adCtrl.text.trim(),
          telegramUrl: _tgCtrl.text.trim(),
        );
        final name = "oversea_${DateTime.now().millisecondsSinceEpoch}.ovsea";
        // File only — no plaintext, no blob in the message text.
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
      _snack("Export failed: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                if (_lock) _showQr = false; // a QR would expose the plain config
              }),
              title: const Text("Lock (export as protected file)"),
              subtitle: const Text("Only Oversea can open it. Share as a file."),
              secondary: const Icon(Icons.lock, color: _accent),
            ),
            if (_lock) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _adCtrl,
                decoration: const InputDecoration(
                  labelText: "Ad text (shown to whoever opens it)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tgCtrl,
                decoration: const InputDecoration(
                  labelText: "Telegram channel URL",
                  hintText: "https://t.me/yourchannel",
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: c.raw));
                        _snack("Config copied");
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text("Copy"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _showQr = !_showQr),
                      icon: const Icon(Icons.qr_code, size: 18),
                      label: Text(_showQr ? "Hide QR" : "QR code"),
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
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_lock ? Icons.lock : Icons.share),
              label: Text(_lock ? "Lock & share file" : "Share"),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  ADD — paste from clipboard / type / import a locked file (Xray only)
// ══════════════════════════════════════════════════════════════════════
class AddScreen extends StatefulWidget {
  final VoidCallback onAdded;
  const AddScreen({super.key, required this.onAdded});
  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _ctrl = TextEditingController();
  final _store = ConfigStore();
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _say(String m, {required bool ok}) => setState(() {
        _result = m;
        _ok = ok;
      });

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text ?? "";
    if (t.isEmpty) {
      _say("Clipboard is empty.", ok: false);
      return;
    }
    _ctrl.text = t;
  }

  /// Add whatever is in the text box: either plain Xray config lines or a
  /// pasted locked blob.
  Future<void> _addText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      if (LockedConfigCodec.looksLocked(text)) {
        await _importLocked(text);
        return;
      }
      final all = ConfigParser.parseMany(text);
      final xray = all.where((c) => c.protocol.isXray).toList();
      if (xray.isEmpty) {
        _say("No supported Xray config found (VLESS / VMess / Trojan / Shadowsocks).",
            ok: false);
        return;
      }
      await _store.add(xray);
      final skipped = all.length - xray.length;
      _ctrl.clear();
      _say("Added ${xray.length} config(s)${skipped > 0 ? ", skipped $skipped unsupported" : ""}.",
          ok: true);
      widget.onAdded();
    } catch (e) {
      _say("Error: $e", ok: false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: true);
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      await _importLocked(utf8.decode(bytes));
    } catch (e) {
      _say("Could not read file: $e", ok: false);
    }
  }

  Future<void> _importLocked(String blob) async {
    if (!LockedConfigCodec.hasKey) {
      _say("This build cannot open locked files.", ok: false);
      return;
    }
    final env = await LockedConfigCodec.decodeConfig(blob);
    final parsed =
        ConfigParser.parseMany(env.config).where((c) => c.protocol.isXray).toList();
    if (parsed.isEmpty) {
      _say("File opened but contains no supported Xray config.", ok: false);
      return;
    }
    // Locked configs keep their server hidden and cannot be copied or re-shared.
    final stored = parsed
        .map((c) => VpnConfig(
              id: c.id,
              name: c.name,
              protocol: c.protocol,
              raw: c.raw,
              source: "locked",
              adText: env.adText,
              telegramUrl: env.telegramUrl,
              locked: true,
            ))
        .toList();
    await _store.add(stored);
    _ctrl.clear();
    _say("Imported ${stored.length} locked config(s).", ok: true);
    widget.onAdded();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add config")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: "vless:// vmess:// trojan:// ss://  …",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste, size: 18),
                    label: const Text("Paste"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _addText,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("Add"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text("Import locked file (.ovsea)"),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_ok ? Colors.green : Colors.red).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _ok ? Colors.green : Colors.red),
                ),
                child: Text(_result!,
                    style: TextStyle(color: _ok ? Colors.green : Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
