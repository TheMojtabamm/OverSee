// Minimal SHA-256 / HMAC-SHA256 (FIPS 180-4, RFC 2104). No dependencies, so the lock
// secret never has to pass through a third-party crypto library or the Dart VM.
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace ovs {

struct Sha256 {
  uint32_t h[8];
  uint64_t len = 0;
  uint8_t buf[64];
  size_t n = 0;
  Sha256();
  void update(const uint8_t* p, size_t k);
  void final(uint8_t out[32]);
};

void sha256(const uint8_t* p, size_t k, uint8_t out[32]);
void hmac_sha256(const uint8_t* key, size_t klen, const uint8_t* msg, size_t mlen, uint8_t out[32]);

}  // namespace ovs
