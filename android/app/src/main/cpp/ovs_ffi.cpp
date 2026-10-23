// C ABI called from Dart (dart:ffi). Only these three symbols are exported.
#include <cstring>
#include <string>

#include "ovs_core.h"

#ifndef OVS_P1
#define OVS_P1 ""
#endif
#ifndef OVS_P2
#define OVS_P2 ""
#endif
#ifndef OVS_P3
#define OVS_P3 ""
#endif
#ifndef OVS_P4
#define OVS_P4 ""
#endif
#ifndef OVS_GATE
#define OVS_GATE ""
#endif
#ifndef OVS_MASK
#define OVS_MASK ""
#endif

namespace {
ovs::Secrets embedded() {
  ovs::Secrets s;
  s.p[0] = OVS_P1; s.p[1] = OVS_P2; s.p[2] = OVS_P3; s.p[3] = OVS_P4;
  s.gate = OVS_GATE; s.mask_hex = OVS_MASK;
  return s;
}
}  // namespace

#define EXPORT extern "C" __attribute__((visibility("default")))

// Bit 0: lock key configured, bit 1: gate key configured.
EXPORT int ovs_capabilities() {
  ovs::Secrets s = embedded();
  return (ovs::has_lock_key(s) ? 1 : 0) | (ovs::has_gate_key(s) ? 2 : 0);
}

// out: 32 bytes. Returns 0 on success.
EXPORT int ovs_derive_file_key(int key_generation, const unsigned char* salt, int salt_len,
                               const char* env_tag, unsigned char* out) {
  if (!salt || salt_len <= 0 || !out) return -1;
  return ovs::derive_file_key(embedded(), key_generation, salt, (size_t)salt_len,
                              env_tag ? env_tag : "", out) ? 0 : -2;
}

// out: buffer of at least 65 bytes; receives 64 hex chars + NUL. Returns 0 on success.
EXPORT int ovs_gate_mac(const char* code, const char* creator_fp, long long day, const char* env_tag,
                        char* out) {
  if (!code || !creator_fp || !out) return -1;
  std::string hex;
  if (!ovs::gate_mac(embedded(), code, creator_fp, day, env_tag ? env_tag : "", &hex)) return -2;
  memcpy(out, hex.c_str(), hex.size() + 1);
  return 0;
}
