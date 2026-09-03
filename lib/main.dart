import "dart:typed_data";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:share_plus/share_plus.dart";
import "package:url_launcher/url_launcher.dart";

import "services/locked_config_codec.dart";
import "services/config_store.dart";
import "services/config_parser.dart";
import "models/vpn_config.dart";

void main() => runApp(const OverseaApp());

class OverseaApp extends StatelessWidget {
  const OverseaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Oversea",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF38E1D4),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  ROOT SHELL — 3 tabs
// ══════════════════════════════════════════════════════════════════════
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [
        const MyConfigsScreen(),
        const ImportScreen(),
        const OwnerScreen(),
      ][_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.vpn_lock), label: "Configs"),
          NavigationDestination(icon: Icon(Icons.download), label: "Import"),
          NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: "Owner"),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  MY CONFIGS — stored configs (NO COPY for locked ones)
//  Tap on locked config → show ad/telegram first → then connect.
// ══════════════════════════════════════════════════════════════════════
class MyConfigsScreen extends StatefulWidget {
  const MyConfigsScreen({super.key});
  @override
  State<MyConfigsScreen> createState() => _MyConfigsScreenState();
}

class _MyConfigsScreenState extends State<MyConfigsScreen> {
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
    setState(() {
      _configs = configs;
      _loading = false;
    });
  }

  /// Tap on a config: if locked and has telegramUrl → show ad dialog with
  /// "Open Channel" button → on continue, try to connect.
  Future<void> _connect(VpnConfig c) async {
    if (!mounted) return;
    final isLocked = c.raw.startsWith("locked:");
    final hasAd = c.adText != null && c.adText!.isNotEmpty;
    final hasTg = c.telegramUrl != null && c.telegramUrl!.isNotEmpty;

    // Locked configs with ad/tg → show promotional dialog first
    if (isLocked && (hasAd || hasTg)) {
      final continueConnect = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.campaign, size: 48, color: Color(0xFF38E1D4)),
          title: Text(c.name.isNotEmpty ? c.name : "Channel Update"),
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
                    onPressed: () async {
                      final uri = Uri.parse(c.telegramUrl!);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
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
      if (continueConnect != true) return;
    }

    // Actual connect (tunnel engine placeholder)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${c.name.isNotEmpty ? c.name : c.host ?? "config"} — connecting...")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("My Configs (${_configs.length})"),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.vpn_lock, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("No configs yet.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 8),
                      Text("Tap Import tab to add locked configs.\nOr Owner tab to create locked configs.",
                          style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _configs.length,
                  itemBuilder: (_, i) {
                    final c = _configs[i];
                    final isLocked = c.raw.startsWith("locked:");
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        leading: Icon(
                          c.protocol == VpnProtocol.vless
                              ? Icons.shield
                              : c.protocol == VpnProtocol.vmess
                                  ? Icons.lock
                                  : Icons.wifi,
                          color: const Color(0xFF38E1D4),
                        ),
                        title: Text(c.name.isNotEmpty ? c.name : (c.host ?? "?")),
                        subtitle: Text("${c.protocol.label} • ${c.host ?? "?"}${isLocked ? " 🔒 Locked" : ""}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // NO COPY for locked configs!
                            if (!isLocked)
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: c.raw));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Config copied")),
                                  );
                                },
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
//  IMPORT — paste locked blob → decrypt locally → save (envelope-aware)
// ══════════════════════════════════════════════════════════════════════
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _ctrl = TextEditingController();
  String? _result;
  bool? _success;

  Future<void> _import() async {
    final blob = _ctrl.text.trim();
    if (blob.isEmpty) return;

    try {
      // Use decodeConfig to handle JSON envelope (config + ad + tg)
      final envelope = await LockedConfigCodec.decodeConfig(blob);
      if (envelope.config.isNotEmpty) {
        final configs = ConfigParser.parseMany(envelope.config);
        if (configs.isNotEmpty) {
          // Attach owner metadata to each parsed config
          final decorated = configs.map((c) => c.copyWith(
            adText: envelope.adText,
            telegramUrl: envelope.telegramUrl,
          )).toList();
          final store = ConfigStore();
          await store.add(decorated);
          if (!mounted) return;
          setState(() {
            final name = decorated.first.name;
            final meta = [
              if (envelope.adText != null && envelope.adText!.isNotEmpty) "ad",
              if (envelope.telegramUrl != null && envelope.telegramUrl!.isNotEmpty) "telegram",
            ];
            _result = "✅ Imported: ${name.isNotEmpty ? name : decorated.first.host ?? "config"}"
                "${meta.isNotEmpty ? " (${meta.join(', ')})" : ""}";
            _success = true;
          });
          _ctrl.clear();
        } else {
          setState(() {
            _result = "❌ Decrypted but could not parse config";
            _success = false;
          });
        }
      } else {
        setState(() {
          _result = "❌ Could not decrypt — invalid blob or wrong key";
          _success = false;
        });
      }
    } catch (e) {
      setState(() {
        _result = "❌ Error: $e";
        _success = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Import Config")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.download, size: 48, color: Color(0xFF38E1D4)),
            const SizedBox(height: 12),
            const Text(
              "Paste a locked config blob from Telegram:",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: "Paste locked blob here...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.download),
              label: const Text("Import & Decrypt"),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_success == true)
                      ? Colors.green.withAlpha(25)
                      : Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_success == true) ? Colors.green : Colors.red,
                  ),
                ),
                child: Text(_result!, style: TextStyle(
                  color: (_success == true) ? Colors.green : Colors.red,
                )),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  OWNER — lock config with ad+tg envelope, export file+text
// ══════════════════════════════════════════════════════════════════════
class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key});
  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  final _nameCtrl = TextEditingController();
  final _adCtrl = TextEditingController();
  final _tgCtrl = TextEditingController();
  final _configCtrl = TextEditingController();

  Future<void> _lockAndExport() async {
    final raw = _configCtrl.text.trim();
    if (raw.isEmpty) return;

    try {
      final ad = _adCtrl.text.trim();
      final tg = _tgCtrl.text.trim();
      final locked = await LockedConfigCodec.encode(
        raw,
        adText: ad.isNotEmpty ? ad : null,
        telegramUrl: tg.isNotEmpty ? tg : null,
      );

      // Save locked version locally (with metadata on the VpnConfig)
      final parsed = ConfigParser.parseMany(raw);
      if (parsed.isEmpty) {
        _snack("❌ Could not parse config");
        return;
      }
      final store = ConfigStore();
      await store.add(parsed.map((c) => c.copyWith(
        raw: "locked:$locked",
        adText: ad.isNotEmpty ? ad : null,
        telegramUrl: tg.isNotEmpty ? tg : null,
      )).toList());

      // Export both text and file via share sheet
      final fileName = "oversea_config_${DateTime.now().millisecondsSinceEpoch}.txt";
      await Share.shareXFiles([
        XFile.fromData(
          Uint8List.fromList(locked.codeUnits),
          name: fileName,
          mimeType: "text/plain",
        )
      ], text: "Locked config for Oversea app:\n$locked");

      _configCtrl.clear();
      _snack("✅ Locked & exported! Share via Telegram.");
    } catch (e) {
      _snack("❌ Lock failed: $e");
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Owner Dashboard")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Channel Settings (ad text + telegram URL)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.campaign, color: Color(0xFF38E1D4)),
                        const SizedBox(width: 8),
                        Text("Channel Settings", style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: "Channel name",
                        border: OutlineInputBorder(),
                        hintText: "My Channel",
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _adCtrl,
                      decoration: const InputDecoration(
                        labelText: "Ad text (shown before connect)",
                        border: OutlineInputBorder(),
                        hintText: "Join our channel @example",
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tgCtrl,
                      decoration: const InputDecoration(
                        labelText: "Telegram URL",
                        border: OutlineInputBorder(),
                        hintText: "https://t.me/yourchannel",
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Lock config
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock, color: Color(0xFF38E1D4)),
                        const SizedBox(width: 8),
                        Text("Lock & Export", style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Paste raw config (vless://, vmess://, ss://, etc.).\nAd text and Telegram URL above are embedded inside the locked blob.",
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _configCtrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: "vless://uuid@host:443?...#Name",
                        border: OutlineInputBorder(),
                        labelText: "Raw config",
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _lockAndExport,
                      icon: const Icon(Icons.lock),
                      label: const Text("Lock & Export (Text + File)"),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
