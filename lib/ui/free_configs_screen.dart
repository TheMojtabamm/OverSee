import "package:flutter/material.dart";

import "../models/vpn_config.dart";
import "../services/config_store.dart";
import "../services/free_configs_service.dart";

/// In-app feed of channels publishing free configs. Lists channels; tapping one
/// loads its configs and lets the user import them into their own list.
class FreeConfigsScreen extends StatefulWidget {
  final String feedBaseUrl;
  const FreeConfigsScreen({super.key, required this.feedBaseUrl});

  @override
  State<FreeConfigsScreen> createState() => _FreeConfigsScreenState();
}

class _FreeConfigsScreenState extends State<FreeConfigsScreen> {
  late final FreeConfigsService _service = FreeConfigsService(widget.feedBaseUrl);
  List<FreeChannel>? _channels;
  String? _error;
  bool _loading = false;

  bool get _configured =>
      widget.feedBaseUrl.isNotEmpty &&
      !widget.feedBaseUrl.contains("feed.example.com");

  @override
  void initState() {
    super.initState();
    if (_configured) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await _service.channels();
      setState(() {
        _channels = c;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = "$e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Free configs"),
        actions: [
          if (_configured)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_configured) {
      return const _Centered(
        icon: Icons.public,
        text: "Set the feed server URL (kFreeFeedBaseUrl) in main.dart to "
            "enable the free-config feed.",
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _Centered(icon: Icons.error_outline, text: "Error: $_error");
    }
    final channels = _channels ?? [];
    if (channels.isEmpty) {
      return const _Centered(icon: Icons.inbox, text: "No channels yet.");
    }
    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (_, i) {
        final ch = channels[i];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.campaign)),
          title: Text(ch.title),
          subtitle: Text("${ch.configCount} configs"),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    _ChannelConfigsScreen(service: _service, channel: ch)),
          ),
        );
      },
    );
  }
}

class _ChannelConfigsScreen extends StatefulWidget {
  final FreeConfigsService service;
  final FreeChannel channel;
  const _ChannelConfigsScreen({required this.service, required this.channel});

  @override
  State<_ChannelConfigsScreen> createState() => _ChannelConfigsScreenState();
}

class _ChannelConfigsScreenState extends State<_ChannelConfigsScreen> {
  final _store = ConfigStore();
  List<VpnConfig>? _configs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.service.configsOf(widget.channel);
      setState(() => _configs = c);
    } catch (e) {
      setState(() => _error = "$e");
    }
  }

  Future<void> _addAll() async {
    final all = _configs ?? [];
    if (all.isEmpty) return;
    await _store.add(all);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Imported ${all.length} configs")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final configs = _configs;
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.title)),
      floatingActionButton: (configs != null && configs.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _addAll,
              icon: const Icon(Icons.download),
              label: const Text("Import all"),
            )
          : null,
      body: _error != null
          ? _Centered(icon: Icons.error_outline, text: "Error: $_error")
          : configs == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: configs.length,
                  itemBuilder: (_, i) {
                    final c = configs[i];
                    return ListTile(
                      leading: CircleAvatar(
                          child: Text(c.protocol.label.substring(0, 1))),
                      title: Text(c.name),
                      subtitle: Text(c.protocol.label),
                      trailing: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          await _store.add([c]);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Added")),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Centered({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
