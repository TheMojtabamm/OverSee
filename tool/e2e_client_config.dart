// Prints the Xray client config the app would build for a link, optionally with a
// gate token, so an end-to-end run can drive it. Used by tool/e2e_gate.sh.
//
//   dart run tool/e2e_client_config.dart <link> [<app-key> <lock-code> <creator-fp>]
import "package:oversea/domain/gate_token.dart";
import "package:oversea/domain/xray_config_builder.dart";

void main(List<String> a) {
  final token =
      a.length >= 4 ? GateToken.forKey(a[1], a[2], a[3], DateTime.now()) : null;
  // ignore: avoid_print
  print(XrayConfigBuilder.build(a[0], TunnelOptions(gateToken: token)));
}
