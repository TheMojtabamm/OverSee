#include "ovs_core.h"
#include "obf.h"

#include <cstring>

#include "sha256.h"

namespace ovs {
namespace {
int hexv(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

std::vector<uint8_t> from_hex(const std::string& h) {
  std::vector<uint8_t> out;
  for (size_t i = 0; i + 1 < h.size(); i += 2) {
    int a = hexv(h[i]), b = hexv(h[i + 1]);
    if (a < 0 || b < 0) break;
    out.push_back((uint8_t)(a * 16 + b));
  }
  return out;
}

std::string to_hex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s;
  for (size_t i = 0; i < n; i++) { s += d[p[i] >> 4]; s += d[p[i] & 15]; }
  return s;
}

// Fixed mixing constant of the format (same as LockedConfigCodec._mask).
const uint8_t kMix[8] = {0x5e, 0x27, 0x93, 0xc1, 0x6f, 0x0a, 0xd8, 0x44};
}  // namespace

std::string unmask(const std::string& embedded, const std::string& mask_hex, int index) {
  if (mask_hex.empty() || embedded.empty()) return embedded;
  std::vector<uint8_t> data = from_hex(embedded), mask = from_hex(mask_hex);
  if (mask.empty()) return embedded;
  std::string out;
  for (size_t i = 0; i < data.size(); i++)
    out += (char)(data[i] ^ mask[i % mask.size()] ^ (uint8_t)((index * 31 + (int)i * 7) & 0xFF));
  return out;
}

bool has_lock_key(const Secrets& s) {
  for (const auto& p : s.p) if (p.empty()) return false;
  return true;
}
bool has_gate_key(const Secrets& s) { return !s.gate.empty(); }

bool derive_file_key(const Secrets& s, int gen, const uint8_t* salt, size_t salt_len,
                     const std::string& env_tag, uint8_t out[32]) {
  if (!has_lock_key(s)) return false;
  // key material = assembled secret || "ovsea|v3|gen<N>" [|| "|env:<tag>"]
  std::vector<uint8_t> key;
  for (int p = 0; p < 4; p++) {
    std::string part = unmask(s.p[p], s.mask_hex, p);
    for (size_t i = 0; i < part.size(); i++)
      key.push_back((uint8_t)((uint8_t)part[i] ^ kMix[i % 8] ^ (uint8_t)(p * 31)));
  }
  std::string tail = OBF("ovsea|v3|gen") + std::to_string(gen);
  if (!env_tag.empty()) tail += OBF("|env:") + env_tag;
  key.insert(key.end(), tail.begin(), tail.end());

  // acc = HMAC(key, salt || "ovsea-lock-v3"); then 4095 more rounds acc = HMAC(key, acc)
  std::vector<uint8_t> msg(salt, salt + salt_len);
  const std::string dom = OBF("ovsea-lock-v3");
  msg.insert(msg.end(), dom.begin(), dom.end());
  uint8_t acc[32];
  hmac_sha256(key.data(), key.size(), msg.data(), msg.size(), acc);
  for (int i = 1; i < 4096; i++) {
    uint8_t next[32];
    hmac_sha256(key.data(), key.size(), acc, 32, next);
    memcpy(acc, next, 32);
  }
  memcpy(out, acc, 32);
  // best effort wipe of the assembled secret
  volatile uint8_t* v = key.data();
  for (size_t i = 0; i < key.size(); i++) v[i] = 0;
  return true;
}

bool gate_mac(const Secrets& s, const std::string& code, const std::string& fp, long long day,
              const std::string& env_tag, std::string* hex_out) {
  if (!has_gate_key(s)) return false;
  std::string key = unmask(s.gate, s.mask_hex, 4);
  if (!env_tag.empty()) key += OBF("|env:") + env_tag;
  std::string msg = OBF("ovsea-gate-v2|") + code + OBF("|") + fp + OBF("|") + std::to_string(day);
  uint8_t mac[32];
  hmac_sha256((const uint8_t*)key.data(), key.size(), (const uint8_t*)msg.data(), msg.size(), mac);
  *hex_out = to_hex(mac, 32);
  return true;
}

}  // namespace ovs
