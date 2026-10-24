// Compile-time XOR for string literals, so the domain-separation strings of the key
// derivation ("ovsea-lock-v3", "ovsea-gate-v2|", …) are not readable with `strings` in
// libovs.so. This raises the cost of finding the construction; it is not encryption.
#pragma once
#include <cstddef>
#include <string>

namespace ovs {

template <size_t N, unsigned char K>
struct ObfStr {
  char d[N];
  constexpr ObfStr(const char (&s)[N]) : d{} {
    for (size_t i = 0; i < N; i++) d[i] = (char)((unsigned char)s[i] ^ (unsigned char)(K + i * 7));
  }
};

// Decoded through a volatile read so the optimiser cannot fold the plain text back in.
template <size_t N, unsigned char K>
__attribute__((noinline)) std::string deobf(const ObfStr<N, K>& o) {
  std::string out(N - 1, '\0');
  const volatile char* p = o.d;
  for (size_t i = 0; i + 1 < N; i++)
    out[i] = (char)((unsigned char)p[i] ^ (unsigned char)(K + i * 7));
  return out;
}

}  // namespace ovs

#define OBF(lit)                                                              \
  ([]() -> std::string {                                                      \
    static constexpr ovs::ObfStr<sizeof(lit), (unsigned char)(__LINE__ * 37 + 11)> \
        kObf(lit);                                                            \
    return ovs::deobf(kObf);                                                  \
  }())
