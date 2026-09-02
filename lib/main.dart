import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:http/http.dart" as http;
import "package:shared_preferences/shared_preferences.dart";

// ── Server URL ──────────────────────────────────────────────────────
// Points at the local dev server; change for production.
const String kBaseUrl = "http://10.0.2.2:8080"; // Android emulator localhost

// ── Entry ───────────────────────────────────────────────────────────
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

// ── Root Shell (bottom nav) ────────────────────────────────────────
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
      const FreeConfigsScreen(),
      const OwnerScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wifi), label: "Configs"),
          NavigationDestination(icon: Icon(Icons.admin_panel_settings), label: "Owner"),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
//  PUBLIC FEED SCREEN — shows channels + locked configs for import
// ══════════════════════════════════════════════════════════════════════
class FreeConfigsScreen extends StatefulWidget {
  const FreeConfigsScreen({super.key});
  @override
  State<FreeConfigsScreen> createState() => _FreeConfigsScreenState();
}

class _FreeConfigsScreenState extends State<FreeConfigsScreen> {
  List<dynamic> _channels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await http.get(Uri.parse("$kBaseUrl/v1/channels"));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() {
          _channels = data["channels"] ?? [];
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Free Configs")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _channels.isEmpty
              ? const Center(child: Text("No channels yet.\nCreate one in the Owner tab.",
                  textAlign: TextAlign.center))
              : ListView.builder(
                  itemCount: _channels.length,
                  itemBuilder: (_, i) {
                    final ch = _channels[i];
                    return ListTile(
                      leading: const Icon(Icons.public),
                      title: Text(ch["title"] ?? "?"),
                      subtitle: Text("${ch["configCount"] ?? 0} configs"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showConfigs(ch["ref"]),
                    );
                  },
                ),
    );
  }

  void _showConfigs(String ref) async {
    try {
      final r = await http.get(Uri.parse("$kBaseUrl/v1/channels/$ref/configs"));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final configs = data["configs"] ?? [];
        final ad = data["ad"] ?? {};
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("Configs for $ref"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ad["text"] != null) ...[
                  Text(ad["text"], style: const TextStyle(color: Colors.amber)),
                  const SizedBox(height: 12),
                ],
                ...configs.map<Widget>((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(c["data"] ?? "empty",
                      style: const TextStyle(fontSize: 11, fontFamily: "monospace")),
                )),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ],
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }
}

// ══════════════════════════════════════════════════════════════════════
//  OWNER SCREEN — register/login → create channel → lock config → export
// ══════════════════════════════════════════════════════════════════════
class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key});
  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  String? _token;
  String _email = "";
  String _password = "";
  List<dynamic> _channels = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final sp = await SharedPreferences.getInstance();
    final tok = sp.getString("owner_token");
    if (tok != null) {
      setState(() => _token = tok);
      _loadChannels();
    }
  }

  Future<void> _saveToken(String t) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString("owner_token", t);
    setState(() => _token = t);
  }

  // ── Auth ────────────────────────────────────────────────────────
  Future<void> _auth(String path) async {
    setState(() => _loading = true);
    try {
      final r = await http.post(
        Uri.parse("$kBaseUrl/v1/owner/$path"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": _email, "password": _password}),
      );
      final data = jsonDecode(r.body);
      if (r.statusCode == 200 && data["token"] != null) {
        await _saveToken(data["token"]);
        _loadChannels();
      } else {
        _snack(data["error"] ?? "auth failed (${r.statusCode})");
      }
    } catch (e) {
      _snack("Error: $e");
    }
    setState(() => _loading = false);
  }

  // ── Channels ────────────────────────────────────────────────────
  Future<void> _loadChannels() async {
    if (_token == null) return;
    try {
      final r = await http.get(
        Uri.parse("$kBaseUrl/v1/owner/channels"),
        headers: {"Authorization": "Bearer $_token"},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        setState(() => _channels = data["channels"] ?? []);
      }
    } catch (_) {}
  }

  Future<void> _createChannel() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("New Channel"),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: "Title")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final r = await http.post(
                Uri.parse("$kBaseUrl/v1/owner/channels"),
                headers: {"Content-Type": "application/json", "Authorization": "Bearer $_token"},
                body: jsonEncode({"title": ctrl.text}),
              );
              if (r.statusCode == 200) _loadChannels();
              else _snack("create failed");
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  // ── Lock config → export file ───────────────────────────────────
  Future<void> _lockConfig(String ref) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Lock Config"),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: "Paste raw config (vless://, vmess://, ...)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final r = await http.post(
                Uri.parse("$kBaseUrl/v1/owner/channels/$ref/blobs"),
                headers: {"Content-Type": "application/json", "Authorization": "Bearer $_token"},
                body: jsonEncode({"config": ctrl.text}),
              );
              if (r.statusCode == 200) {
                final data = jsonDecode(r.body);
                _exportLocked(data);
              } else {
                final data = jsonDecode(r.body);
                _snack(data["error"] ?? "lock failed");
              }
            },
            child: const Text("Lock & Export"),
          ),
        ],
      ),
    );
  }

  void _exportLocked(Map<String, dynamic> data) {
    final locked = data["locked"] ?? "";
    final blobId = data["blobId"] ?? "";
    final meta = data["meta"] ?? {};
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("✅ Locked Config"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Protocol: ${meta["protocol"] ?? "?"}"),
            Text("Host: ${meta["host"] ?? "?"}"),
            Text("Title: ${meta["title"] ?? "?"}"),
            const Divider(),
            const Text("Locked blob (copy & share):",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(locked, style: const TextStyle(fontSize: 10, fontFamily: "monospace")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // ── Not logged in → show auth form ──
    if (_token == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Owner")),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.admin_panel_settings, size: 64, color: Color(0xFF38E1D4)),
              const SizedBox(height: 24),
              TextField(
                decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder()),
                onChanged: (v) => _email = v,
              ),
              const SizedBox(height: 12),
              TextField(
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
                onChanged: (v) => _password = v,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => _auth("register"),
                      child: const Text("Register"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading ? null : () => _auth("login"),
                      child: const Text("Login"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // ── Logged in → channel list ──
    return Scaffold(
      appBar: AppBar(
        title: const Text("Owner Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChannels,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final sp = await SharedPreferences.getInstance();
              await sp.remove("owner_token");
              setState(() {
                _token = null;
                _channels = [];
              });
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createChannel,
        child: const Icon(Icons.add),
      ),
      body: _channels.isEmpty
          ? const Center(child: Text("No channels yet.\nTap + to create one."))
          : ListView.builder(
              itemCount: _channels.length,
              itemBuilder: (_, i) {
                final ch = _channels[i];
                final ref = ch["ref"] ?? "";
                final stats = ch["stats"] ?? {};
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(ch["title"] ?? "?",
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        "configs: ${ch["configCount"] ?? 0}  •  "
                        "live: ${stats["liveConnections"] ?? 0}  •  "
                        "total: ${stats["totalConnections"] ?? 0}"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showChannelDetail(ref, ch),
                  ),
                );
              },
            ),
    );
  }

  void _showChannelDetail(String ref, Map<String, dynamic> ch) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        expand: false,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(ch["title"] ?? "?", style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text("ref: $ref", style: const TextStyle(color: Colors.grey)),
            if (ch["adText"] != null && ch["adText"] != "")
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text("Ad: ${ch["adText"]}", style: const TextStyle(color: Colors.amber)),
              ),
            const Divider(height: 24),
            FilledButton.icon(
              onPressed: () { Navigator.pop(context); _lockConfig(ref); },
              icon: const Icon(Icons.lock),
              label: const Text("Lock New Config"),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); _revokeChannel(ref); },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text("Revoke Channel", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  void _revokeChannel(String ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Revoke Channel?"),
        content: const Text("This will revoke ALL configs. Irreversible."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text("Revoke", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final r = await http.delete(
      Uri.parse("$kBaseUrl/v1/owner/channels/$ref"),
      headers: {"Authorization": "Bearer $_token"},
    );
    if (r.statusCode == 200) {
      _loadChannels();
    } else {
      _snack("revoke failed");
    }
  }
}
