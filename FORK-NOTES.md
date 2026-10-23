# Fork notes

## Source deviations

- `src/`: upstream cJSON sources are unchanged.
- `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`: copied from the workspace runtime core; the SPDX line is MIT for this package's terms.
- `runtime/sync.h`: copied from the workspace runtime core; the SPDX line is MIT and the include guard is `CJSON_RUNTIME_SYNC_H` for this package.
- `runtime/graph.zig`: package-specific module wiring, synchronization prefix, and routed-symbol classification.
- `runtime/library.zig`: package-specific synchronization binding, ABI declaration, and provider checks.

## Build graph deviations

- `build.zig` compiles `src/cJSON.c` as `libcjson`; upstream builds `src/cJSON_Utils.c` as a separate library, so this package does not add its symbols to `libcjson`.
- The build uses Zig instead of upstream's CMake or Makefile and needs no configure or download step because the source tree is vendored.
- The Zig facade uses a translated upstream header. Runtime-loading builds dispatch through an explicitly selected provider and do not link the archive into the module.
- The build uses upstream's locale and symbol-visibility flags. It adds no linker export list; the header's export macros define the symbols.
- There is no system-library mode. `CJSON_NESTING_LIMIT` is a compile-time setting, so an installed header can describe different behavior from its library.

## Platform boundaries

- WASI has no dynamic linker. A request for `-Dlinkage=dynamic` is refused; static linkage remains available.
- macOS shared objects can export more globals than ELF builds because `ld64` exports globals by default and this build has no first-class way to narrow that table.
- On `armeb-linux`, a variadic `double` can arrive with its 32-bit halves exchanged at the big-endian ARM VFP call boundary under QEMU and the pinned toolchain. A cJSON-free C program reproduces the issue, which can fail cJSON's byte-exact number-format test before `sprintf` receives the intended value.
- cJSON formats numbers with `sprintf` `%g` conversions. C libraries can differ on a leading space or a three-digit exponent, so exact output expectations can vary by platform.
