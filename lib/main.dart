import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "services/locked_config_codec.dart";
import "services/config_store.dart";
import "services/config_parser.dart" show ConfigParser;
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
//  MY CONFIGS — list stored configs
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
                      Text("Tap Import tab to add configs.",
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _configs.length,
                  itemBuilder: (_, i) {
                    final c = _configs[i];
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
                        subtitle: Text("${c.protocol.label} • ${c.host ?? "?"}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                      ),
                    );
                  },
                ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  IMPORT — paste locked blob → decrypt locally → save
// ══════════════════════════════════════════════════════════════════════
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _ctrl = TextEditingController();
  String? _result;
  bool? _success; // null = no attempt yet

  Future<void> _import() async {
    final blob = _ctrl.text.trim();
    if (blob.isEmpty) return;

    try {
      final decoded = await LockedConfigCodec.decode(blob);
      if (decoded != null && decoded.isNotEmpty) {
        final configs = ConfigParser.parseMany(decoded);
        if (configs.isNotEmpty) {
          final store = ConfigStore();
          await store.add(configs);
          if (!mounted) return;
          setState(() {
            final name = configs.first.name;
            _result = "✅ Imported: ${name.isNotEmpty ? name : configs.first.host ?? "config"}";
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
//  OWNER — lock config locally, export locked blob for Telegram
// ══════════════════════════════════════════════════════════════════════
class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key});
  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  final _ctrl = TextEditingController();
  String? _lockedResult;
  bool? _locked;

  Future<void> _lockConfig() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;

    try {
      final locked = await LockedConfigCodec.encode(raw);
      setState(() {
        _lockedResult = locked;
        _locked = true;
      });
    } catch (e) {
      setState(() {
        _lockedResult = "❌ Lock failed: $e";
        _locked = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Owner — Lock Config")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.admin_panel_settings, size: 48, color: Color(0xFF38E1D4)),
            const SizedBox(height: 12),
            const Text(
              "Paste your raw config below to lock it.\n"
              "The locked blob can be shared on Telegram.\n"
              "Only Oversea app can decrypt it.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: "vless://uuid@host:443?...#Name",
                border: OutlineInputBorder(),
                labelText: "Raw config",
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _lockConfig,
              icon: const Icon(Icons.lock),
              label: const Text("Lock Config"),
            ),
            if (_locked != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_locked == true)
                      ? Colors.green.withAlpha(25)
                      : Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_locked == true) ? Colors.green : Colors.red,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _locked == true ? "✅ Locked!" : _lockedResult!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: (_locked == true) ? Colors.green : Colors.red,
                      ),
                    ),
                    if (_locked == true) ...[
                      const SizedBox(height: 8),
                      const Text("Locked blob (copy & paste to Telegram):",
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 4),
                      SelectableText(
                        _lockedResult!,
                        style: const TextStyle(fontSize: 10, fontFamily: "monospace"),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.tonal(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _lockedResult!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("✅ Copied!")),
                              );
                            },
                            child: const Text("📋 Copy"),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonal(
                            onPressed: () {
                              _ctrl.clear();
                              setState(() {
                                _lockedResult = null;
                                _locked = null;
                              });
                            },
                            child: const Text("🔄 New Config"),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
