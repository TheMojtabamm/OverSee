// Lock key derivation and gate token, in native code.
//
// The Dart side asks "give me the AES key for this salt" / "give me the gate MAC for
// this lock"; the secret parts, the mask and the stretch live here, not in the Dart
// snapshot. Output is bit-for-bit what lib/domain/locked_config_codec.dart and
// lib/domain/gate_token.dart compute (checked by test/native_core_test.dart).
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace ovs {

struct Secrets {
  // Embedded values, either plain (dev) or hex(secret XOR mask) when mask_hex is set.
  std::string p[4];
  std::string gate;
  std::string mask_hex;
};

// Recover a secret from its embedded form (mirror of SecretMask.unmask in Dart).
std::string unmask(const std::string& embedded, const std::string& mask_hex, int index);

bool has_lock_key(const Secrets& s);
bool has_gate_key(const Secrets& s);

// 32-byte AES-256 key for a file with this 16-byte salt. env_tag is "" when clean.
bool derive_file_key(const Secrets& s, int key_generation, const uint8_t* salt, size_t salt_len,
                     const std::string& env_tag, uint8_t out[32]);

// hex(HMAC(appKey[|env:tag], "ovsea-gate-v2|code|fp|day"))
bool gate_mac(const Secrets& s, const std::string& code, const std::string& creator_fp, long long day,
              const std::string& env_tag, std::string* hex_out);

}  // namespace ovs
