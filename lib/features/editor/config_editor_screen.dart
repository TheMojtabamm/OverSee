import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/tunnel_service.dart";
import "../../domain/config_draft.dart";
import "../../domain/config_parser.dart";
import "../../domain/vpn_config.dart";
import "../../providers.dart";
import "../../ui/theme.dart";
import "../../ui/widgets.dart";

/// Create a config from scratch, or edit an unlocked one. The form fills in a [ConfigDraft];
/// saving turns it back into a share link, so the rest of the app sees an ordinary config.
class ConfigEditorScreen extends ConsumerStatefulWidget {
  /// The config being edited; null = create a new one.
  final VpnConfig? existing;
  const ConfigEditorScreen({super.key, this.existing});

  @override
  ConsumerState<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends ConsumerState<ConfigEditorScreen> {
  late ConfigDraft d;
  bool _submitted = false;
  bool _saving = false;
  bool _editable = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex == null) {
      d = ConfigDraft.blank(DraftProtocol.vless);
    } else {
      final parsed = ConfigDraft.fromLink(ex.raw);
      _editable = parsed != null && !ex.locked;
      d = parsed ?? ConfigDraft.blank(DraftProtocol.vless);
    }
  }

  Map<String, String> get _errs => _submitted ? d.errors() : const {};

  void _switchProtocol(DraftProtocol p) {
    final old = d;
    d = ConfigDraft.blank(p)
      ..name = old.name
      ..address = old.address
      ..port = p == DraftProtocol.shadowsocks && old.port == "443"
          ? "8388"
          : old.port;
    setState(() {});
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (d.errors().isNotEmpty) return;
    final link = d.toLink();
    final parsed = ConfigParser.parseLine(link, source: "manual");
    if (parsed == null || parsed.protocol == VpnProtocol.unknown) {
      _toast("Those settings don't make a valid config");
      return;
    }
    setState(() => _saving = true);
    final ex = widget.existing;
    if (ex == null) {
      await ref.read(configsProvider.notifier).addAll([parsed]);
      ref.read(selectedConfigIdProvider.notifier).select(parsed.id);
    } else {
      await ref.read(configsProvider.notifier).saveEdited(
          parsed.copyWith(id: ex.id, source: "manual", clearChannelRef: true));
    }
    if (!mounted) return;
    final running = ex != null &&
        ref.read(activeConfigIdProvider) == ex.id &&
        ref.read(tunnelStateProvider).valueOrNull?.phase ==
            TunnelPhase.connected;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
        content: Text(running
            ? "Saved. Reconnect to use the new settings."
            : (ex == null ? "Config added" : "Saved"))));
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  // ---- field helpers --------------------------------------------------------

  Widget _tf(
    String id,
    String label,
    String value,
    ValueChanged<String> onChanged, {
    String? errorKey,
    String? hint,
    TextInputType? keyboard,
    bool ltr = true,
    List<TextInputFormatter>? formatters,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        key: ValueKey("${d.protocol.name}-$id"),
        initialValue: value,
        keyboardType: keyboard,
        maxLines: maxLines,
        inputFormatters: formatters,
        textDirection: ltr ? TextDirection.ltr : null,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: (v) {
          onChanged(v);
          if (_submitted) setState(() {});
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorKey == null ? null : _errs[errorKey],
        ),
      ),
    );
  }

  Widget _drop(String label, String value, List<String> options,
      ValueChanged<String> onChanged,
      {String Function(String)? text}) {
    final list = options.contains(value) ? options : [value, ...options];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey("$label-$value-${d.protocol.name}"),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        borderRadius: BorderRadius.circular(14),
        items: [
          for (final o in list)
            DropdownMenuItem(value: o, child: Text(text == null ? o : text(o)))
        ],
        onChanged: (v) {
          if (v != null) setState(() => onChanged(v));
        },
      ),
    );
  }

  Widget _choices<T>(String label, T value, List<T> options,
      String Function(T) text, ValueChanged<T> onPick) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: c.muted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(text(o)),
                  selected: o == value,
                  showCheckmark: false,
                  selectedColor: c.brandSoft,
                  side: BorderSide(color: o == value ? c.brand : c.outline),
                  labelStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: o == value ? c.brand : c.muted),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => onPick(o)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children),
            ),
          ),
        ],
      ),
    );
  }

  // ---- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (!_editable) {
      return Scaffold(
        appBar: AppBar(title: const Text("Edit config")),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              "This config can't be edited here. Locked configs stay hidden, and some protocols aren't supported by the editor.",
              style: TextStyle(color: c.muted, height: 1.5)),
        ),
      );
    }

    final p = d.protocol;
    final isSs = p == DraftProtocol.shadowsocks;
    final isUuid = p == DraftProtocol.vless || p == DraftProtocol.vmess;
    final secName = isUuid ? "User ID (UUID)" : "Password";

    final server = <Widget>[
      _tf("name", "Name", d.name, (v) => d.name = v,
          hint: "Shown in your list", ltr: false),
      _tf("address", "Address", d.address, (v) => d.address = v.trim(),
          errorKey: "address", hint: "example.com or an IP"),
      _tf("port", "Port", d.port, (v) => d.port = v.trim(),
          errorKey: "port",
          keyboard: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly]),
      _tf("secret", secName, d.secret, (v) => d.secret = v.trim(),
          errorKey: "secret"),
      if (p == DraftProtocol.vless)
        _drop(
            "Flow",
            d.flow.isEmpty ? "none" : d.flow,
            const ["none", "xtls-rprx-vision"],
            (v) => d.flow = v == "none" ? "" : v),
      if (p == DraftProtocol.vmess) ...[
        _tf("alterId", "Alter ID", d.alterId, (v) => d.alterId = v.trim(),
            errorKey: "alterId",
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly]),
        _drop("Cipher", d.vmessCipher, ConfigDraft.vmessCiphers,
            (v) => d.vmessCipher = v),
      ],
      if (isSs)
        _drop(
            "Method", d.ssMethod, ConfigDraft.ssMethods, (v) => d.ssMethod = v),
    ];

    final net = d.network;
    final pathy = net == DraftNetwork.ws ||
        net == DraftNetwork.httpupgrade ||
        net == DraftNetwork.xhttp ||
        (net == DraftNetwork.tcp && d.headerType == "http");
    final transport = <Widget>[
      _choices<DraftNetwork>("Network", net, DraftNetwork.values,
          (n) => n.label, (n) => d.network = n),
      if (net == DraftNetwork.tcp)
        _choices<String>("Header", d.headerType, const ["none", "http"],
            (h) => h == "none" ? "None" : "HTTP", (h) => d.headerType = h),
      if (pathy) ...[
        _tf("path", "Path", d.path, (v) => d.path = v, hint: "/"),
        _tf("host", "Host header", d.hostHeader, (v) => d.hostHeader = v.trim(),
            hint: "Usually the domain behind the CDN"),
      ],
      if (net == DraftNetwork.grpc) ...[
        _tf("service", "Service name", d.serviceName, (v) => d.serviceName = v,
            errorKey: "serviceName"),
        _drop("Mode", d.mode.isEmpty ? "gun" : d.mode, const ["gun", "multi"],
            (v) => d.mode = v == "gun" ? "" : v),
      ],
      if (net == DraftNetwork.xhttp)
        _drop(
            "Mode",
            d.mode.isEmpty ? "auto" : d.mode,
            const ["auto", "packet-up", "stream-up", "stream-one"],
            (v) => d.mode = v == "auto" ? "" : v),
    ];

    final secOptions = p == DraftProtocol.vmess
        ? const [DraftSecurity.none, DraftSecurity.tls]
        : DraftSecurity.values;
    final sec = d.security;
    final security = <Widget>[
      _choices<DraftSecurity>(
          "Security", sec, secOptions, (s) => s.label, (s) => d.security = s),
      if (sec != DraftSecurity.none) ...[
        _tf("sni", "Server name (SNI)", d.sni, (v) => d.sni = v.trim(),
            hint: "Leave empty to use the address"),
        _drop("Fingerprint", d.fingerprint, ConfigDraft.fingerprints,
            (v) => d.fingerprint = v),
      ],
      if (sec == DraftSecurity.tls)
        _tf("alpn", "ALPN", d.alpn, (v) => d.alpn = v.trim(),
            hint: "h2,http/1.1"),
      if (sec == DraftSecurity.reality) ...[
        _tf("pbk", "Public key", d.publicKey, (v) => d.publicKey = v.trim(),
            errorKey: "publicKey"),
        _tf("sid", "Short ID", d.shortId, (v) => d.shortId = v.trim()),
        _tf("spx", "Spider X", d.spiderX, (v) => d.spiderX = v.trim()),
      ],
    ];

    final advanced = <Widget>[
      if (p == DraftProtocol.vless)
        _tf("enc", "Encryption", d.encryption, (v) => d.encryption = v.trim(),
            hint: "none"),
      if (sec == DraftSecurity.tls) ...[
        _tf("pcs", "Pinned certificate (SHA-256)", d.pinnedCert,
            (v) => d.pinnedCert = v.trim(),
            hint: "For a self-signed certificate"),
        _tf("vcn", "Verify certificate for name", d.verifyName,
            (v) => d.verifyName = v.trim()),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? "Edit config" : "New config")),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_isEdit ? "Save changes" : "Add config"),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          if (!_isEdit)
            _choices<DraftProtocol>("Protocol", p, DraftProtocol.values,
                (x) => x.label, _switchProtocol)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(children: [Pill(p.label)]),
            ),
          _section("Server", server),
          if (!isSs) _section("Transport", transport),
          if (!isSs) _section("Security", security),
          if (advanced.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: const Text("Advanced",
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    children: advanced,
                  ),
                ),
              ),
            ),
          if (d.extra.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  "${d.extra.length} extra setting${d.extra.length == 1 ? "" : "s"} in this config will be kept as they are.",
                  style: TextStyle(color: c.muted, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}
