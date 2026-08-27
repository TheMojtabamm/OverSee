import "package:flutter/material.dart";

import "models/vpn_config.dart";
import "services/config_parser.dart";
import "services/config_store.dart";
import "services/subscription_service.dart";
import "ui/free_configs_screen.dart";

// Set this to your free-config feed server once it is running.
const String kFreeFeedBaseUrl = "https://feed.example.com";

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

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const ConfigsScreen(),
      const FreeConfigsScreen(feedBaseUrl: kFreeFeedBaseUrl),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.vpn_lock), label: "Configs"),
          NavigationDestination(icon: Icon(Icons.public), label: "Free"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
    );
  }
}

// ───────────────────────── User configs ─────────────────────────
class ConfigsScreen extends StatefulWidget {
  const ConfigsScreen({super.key});
  @override
  State<ConfigsScreen> createState() => _ConfigsScreenState();
}

class _ConfigsScreenState extends State<ConfigsScreen> {
  final _store = ConfigStore();
  List<VpnConfig> _configs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final c = await _store.load();
    setState(() {
      _configs = c;
      _loading = false;
    });
  }

  void _connect(VpnConfig c) {
    // Later phase: the native engine (inside a VpnService) is invoked here.
    // For now we only signal that the tunnel layer is not wired yet.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Connect to \"${c.name}\" — tunnel engine added in a later phase."),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Configs")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddConfigScreen()));
          _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text("Add"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _configs.isEmpty
              ? const Center(child: Text("No configs yet."))
              : ListView.builder(
                  itemCount: _configs.length,
                  itemBuilder: (_, i) {
                    final c = _configs[i];
                    return ListTile(
                      leading: CircleAvatar(
                          child: Text(c.protocol.label.substring(0, 1))),
                      title: Text(c.name),
                      subtitle: Text(
                          "${c.protocol.label}${c.host != null ? " · ${c.host}" : ""}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _connect(c),
                      ),
                      onLongPress: () async {
                        await _store.remove(c.id);
                        _reload();
                      },
                    );
                  },
                ),
    );
  }
}

// ───────────────────────── Add config ─────────────────────────
class AddConfigScreen extends StatefulWidget {
  const AddConfigScreen({super.key});
  @override
  State<AddConfigScreen> createState() => _AddConfigScreenState();
}

class _AddConfigScreenState extends State<AddConfigScreen> {
  final _store = ConfigStore();
  final _text = TextEditingController();
  String? _status;
  bool _busy = false;

  Future<void> _addPasted() async {
    setState(() => _busy = true);
    final parsed = ConfigParser.parseMany(_text.text);
    if (parsed.isEmpty) {
      setState(() {
        _busy = false;
        _status = "Nothing to add.";
      });
      return;
    }
    await _store.add(parsed);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addSub() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final configs = await SubscriptionService.fetch(_text.text.trim());
      await _store.add(configs);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _status = "Error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add config")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              maxLines: 6,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Paste configs here, or put a subscription link…",
              ),
            ),
            const SizedBox(height: 12),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_status!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _addPasted,
                    child: const Text("Add from text"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _addSub,
                    child: const Text("Add from link"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Settings ─────────────────────────
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text("Version"),
            subtitle: Text("1.0.0 — base phase (no tunnel engine yet)"),
          ),
          ListTile(
            leading: Icon(Icons.battery_charging_full),
            title: Text("Battery usage"),
            subtitle: Text("Optimized in the native-engine phase — see README"),
          ),
        ],
      ),
    );
  }
}
