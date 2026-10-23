// The whole lock story with the REAL app code, for tool/e2e_lockflow.sh:
//
//   1. an owner locks a config (signed, gated) -> a .ovsea blob
//   2. a "bot" decodes the blob (assume it extracted the lock secret) and gets the plain link
//   3. the real app imports the same blob and builds its tunnel config (with the gate token)
//   4. a thief re-locks the decoded config under their own identity, and imports THAT in the app
//
// Writes owner/bot/thief Xray client configs + the allow-list line into <outdir>.
//
//   dart run -DLOCK_P1=.. -DLOCK_P2=.. -DLOCK_P3=.. -DLOCK_P4=.. -DGATE_KEY=.. \
//     tool/e2e_lockflow.dart <outdir> <vless link>
import "dart:io";

import "package:oversea/domain/creator_identity.dart";
import "package:oversea/domain/gate_token.dart";
import "package:oversea/domain/locked_config_codec.dart";
import "package:oversea/domain/xray_config_builder.dart";
import "package:oversea/features/add/importer.dart";

Never fail(String m) {
  stderr.writeln("lockflow: $m");
  exit(1);
}

Future<void> main(List<String> a) async {
  if (a.length < 2) fail("usage: <outdir> <link>");
  if (!LockedConfigCodec.hasKey || !GateToken.available) {
    fail("build has no lock key / gate key: pass -DLOCK_P1..P4 and -DGATE_KEY");
  }
  final out = Directory(a[0])..createSync(recursive: true);
  final link = a[1];

  // 1. owner locks with the gate on
  final owner = await CreatorIdentity.generate();
  final code = GateToken.newCode();
  final blob = await LockedConfigCodec.encode(link,
      signer: owner,
      gateCode: code,
      adText: "owner ad",
      telegramUrl: "https://t.me/owner");
  File("${out.path}/allow.txt").writeAsStringSync(
      "${GateToken.allowListLine(code, owner.fingerprint, note: "lockflow")}\n");
  File("${out.path}/blob.ovsea").writeAsStringSync(blob);
  if (blob.contains("vless") ||
      blob.contains(link.split("@").last.split("?").first)) {
    fail("the blob leaks the link in cleartext");
  }

  // 2. a bot decodes it: this is what ends up pasted into other apps / channels
  final bot = await LockedConfigCodec.decodeConfig(blob);
  if (bot.config != link) fail("decode did not recover the original link");
  File("${out.path}/bot.json").writeAsStringSync(
      XrayConfigBuilder.build(bot.config)); // plain link, no token
  File("${out.path}/decoded_link.txt").writeAsStringSync(bot.config);

  // 3. the real app path: Importer -> VpnConfig -> the options connect_flow builds
  Future<String> appConfig(String text) async {
    final imp = await Importer.fromText(text);
    if (!imp.isOk) fail("importer refused: ${imp.errorKey}");
    final c = imp.configs.single;
    if (c.creator == null) fail("imported file has no verified creator");
    final token = GateToken.current(c.gateCode!, c.creator!);
    stdout.writeln(
        "  creator=${c.creator}  gated=${c.gated}  token-day=${token.split(".")[1]}");
    return XrayConfigBuilder.build(c.raw, TunnelOptions(gateToken: token));
  }

  stdout.writeln("owner file in the app:");
  File("${out.path}/app.json").writeAsStringSync(await appConfig(blob));

  // 4. thief: re-lock the decoded config + code under their own identity, open it in the app
  final thief = await CreatorIdentity.generate();
  final blob2 = await LockedConfigCodec.encode(bot.config,
      signer: thief, gateCode: bot.gateCode, adText: "thief ad");
  stdout.writeln("thief's re-locked copy in the app:");
  File("${out.path}/thief.json").writeAsStringSync(await appConfig(blob2));
  if (owner.fingerprint == thief.fingerprint) fail("identities collided");
  stdout.writeln("ok: owner=${owner.fingerprint} thief=${thief.fingerprint}");
}
