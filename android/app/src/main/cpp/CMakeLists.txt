cmake_minimum_required(VERSION 3.18.1)
project(ovs_native CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

add_library(ovs SHARED sha256.cpp ovs_core.cpp ovs_ffi.cpp)

# Secrets arrive as masked hex via -DOVS_P1=... (see android/app/build.gradle.kts).
foreach(v OVS_P1 OVS_P2 OVS_P3 OVS_P4 OVS_GATE OVS_MASK)
  if(DEFINED ${v})
    target_compile_definitions(ovs PRIVATE ${v}="${${v}}")
  endif()
endforeach()

target_compile_options(ovs PRIVATE -O2 -fvisibility=hidden -fno-stack-protector)
target_link_options(ovs PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL -Wl,-z,max-page-size=16384)
