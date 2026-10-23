// Prints the masked --dart-define values CI should build with (one NAME=value per
// line, ready to append to $GITHUB_ENV). Reads the plain secrets from the environment:
//
//   LOCK_P1 LOCK_P2 LOCK_P3 LOCK_P4 GATE_KEY  ->  LOCK_P1_M … GATE_KEY_M, LOCK_MASK
//
// A new random mask is generated on every run, so every build embeds different bytes.
import "dart:io";
import "dart:math";

import "package:oversea/domain/secret_mask.dart";

const _names = ["LOCK_P1", "LOCK_P2", "LOCK_P3", "LOCK_P4", "GATE_KEY"];

void main() {
  final r = Random.secure();
  final mask = SecretMask.hexOf(List.generate(24, (_) => r.nextInt(256)));
  for (var i = 0; i < _names.length; i++) {
    final v = Platform.environment[_names[i]] ?? "";
    stdout.writeln(
        "${_names[i]}_M=${v.isEmpty ? "" : SecretMask.mask(v, mask, i)}");
  }
  stdout.writeln("LOCK_MASK=$mask");
}
