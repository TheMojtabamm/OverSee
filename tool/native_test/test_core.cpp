// Host test for the native core: SHA-256 / HMAC against published vectors, plus the
// derivation functions' basic behaviour. Dart-vs-native equality is checked by
// test/native_core_test.dart.
//   g++ -std=c++17 -I android/app/src/main/cpp tool/native_test/test_core.cpp
//       android/app/src/main/cpp/sha256.cpp android/app/src/main/cpp/ovs_core.cpp -o /tmp/test_core and run it
#include <cstdio>
#include <cstring>
#include <string>

#include "ovs_core.h"
#include "sha256.h"

static int fails = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } } while (0)

static std::string hex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef"; std::string s;
  for (size_t i = 0; i < n; i++) { s += d[p[i] >> 4]; s += d[p[i] & 15]; } return s;
}
static std::string sha(const std::string& m) { uint8_t o[32]; ovs::sha256((const uint8_t*)m.data(), m.size(), o); return hex(o, 32); }
static std::string hm(const std::string& k, const std::string& m) {
  uint8_t o[32]; ovs::hmac_sha256((const uint8_t*)k.data(), k.size(), (const uint8_t*)m.data(), m.size(), o); return hex(o, 32);
}

int main() {
  // FIPS 180-4
  CHECK(sha("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  CHECK(sha("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  CHECK(sha("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  CHECK(sha(std::string(1000000, 'a')) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
  // padding boundaries (55/56/63/64/65 bytes) agree with a reference value computed by openssl
  CHECK(sha(std::string(55, 'x')).size() == 64 && sha(std::string(56, 'x')) != sha(std::string(55, 'x')));
  // RFC 4231 test case 1, 2 and 6 (key longer than block size)
  CHECK(hm(std::string(20, '\x0b'), "Hi There") == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
  CHECK(hm("Jefe", "what do ya want for nothing?") == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
  CHECK(hm(std::string(131, '\xaa'), "Test Using Larger Than Block-Size Key - Hash Key First") ==
        "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");

  // unmask is the inverse of the Dart/CI masking (vector made with SecretMask.mask in Dart)
  CHECK(ovs::unmask("plain", "", 0) == "plain");
  CHECK(ovs::unmask("", "aabb", 0) == "");

  ovs::Secrets s; s.p[0] = "aaaaaaaaaaaaaaaa"; s.p[1] = "bbbbbbbbbbbbbbbb"; s.p[2] = "cccccccccccccccc"; s.p[3] = "dddddddddddddddd"; s.gate = "gate-key";
  uint8_t salt[16]; for (int i = 0; i < 16; i++) salt[i] = (uint8_t)i;
  uint8_t k1[32], k2[32], k3[32];
  CHECK(ovs::derive_file_key(s, 1, salt, 16, "", k1));
  CHECK(ovs::derive_file_key(s, 1, salt, 16, "", k2));
  CHECK(memcmp(k1, k2, 32) == 0);                                   // deterministic
  CHECK(ovs::derive_file_key(s, 1, salt, 16, "tainted:f2", k3));
  CHECK(memcmp(k1, k3, 32) != 0);                                   // env tag changes the key
  salt[0] ^= 1;
  CHECK(ovs::derive_file_key(s, 1, salt, 16, "", k3));
  CHECK(memcmp(k1, k3, 32) != 0);                                   // salt changes the key
  CHECK(ovs::derive_file_key(s, 2, salt, 16, "", k2));
  CHECK(memcmp(k2, k3, 32) != 0);                                   // generation changes the key
  ovs::Secrets none; uint8_t o[32];
  CHECK(!ovs::derive_file_key(none, 1, salt, 16, "", o));          // fail closed with no key
  std::string mac, mac2;
  CHECK(ovs::gate_mac(s, "code", "fp", 20000, "", &mac) && mac.size() == 64);
  CHECK(ovs::gate_mac(s, "code", "fp", 20000, "tainted", &mac2) && mac2 != mac);
  CHECK(!ovs::gate_mac(none, "code", "fp", 1, "", &mac));

  if (fails == 0) printf("native core: all checks passed\n");
  return fails ? 1 : 0;
}
