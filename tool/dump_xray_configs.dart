// Builds an Xray config for every fixture link x option set and writes them to
// the given directory, for tool/validate_xray_config to check with Xray itself.
//
//   dart run tool/dump_xray_configs.dart /tmp/xray_out
import "dart:io";

import "package:oversea/domain/xray_config_builder.dart";

void main(List<String> args) {
  final out = Directory(args.isNotEmpty ? args.first : "build/xray_out")
    ..createSync(recursive: true);
  final links = File("test/fixtures/xray_links.txt")
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty);

  const variants = {
    "default": TunnelOptions(),
    "fragment": TunnelOptions(fragment: true),
    "ipv6": TunnelOptions(ipv6: true, bypassLan: false),
    "plaindns": TunnelOptions(dohServers: []),
    "probe": TunnelOptions(probe: ProbeEndpoint(24680, "u", "p")),
  };

  var n = 0;
  for (final link in links) {
    for (final v in variants.entries) {
      File("${out.path}/${n.toString().padLeft(2, "0")}_${v.key}.json")
          .writeAsStringSync(XrayConfigBuilder.build(link, v.value));
    }
    n++;
  }
  stdout.writeln("wrote ${n * variants.length} configs to ${out.path}");
}
