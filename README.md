# cJSON

cJSON 1.7.19 is a C JSON parser. This package builds it with Zig 0.17.0 and provides a typed Zig facade.
Upstream: [DaveGamble/cJSON](https://github.com/DaveGamble/cJSON), tag `v1.7.19`.

## Source deviations

The vendored `src/` tree is unchanged. The package builds `src/cJSON.c`; it does not include `src/cJSON_Utils.c` in its library, so no `cJSONUtils_*` symbols are provided.

## Build deviations

- Zig builds the library directly; it does not use upstream's CMake or Make build. No download or configure step runs at build time.
- `-Dlinkage=static` is the default. `-Dlinkage=dynamic` uses upstream's shared-object versioning; ELF installs provide `libcjson.so.1.7.19` with soname `libcjson.so.1`.
- `-Druntime=true` enables explicit runtime loading through the Zig facade.
- System-library mode is not available.

## Support matrix

Configured build targets:

| Target | Constraint |
|---|---|
| `x86_64-linux-gnu` | |
| `aarch64-linux-gnu` | |
| `aarch64-macos-none` | Shared builds export more symbols than ELF builds. |
| `x86_64-windows-gnu` | The header defines DLL exports. |
| `riscv64-linux-gnu` | |
| `wasm32-wasi` | Static linked builds only; no runtime provider loading. Dynamic linkage is refused. |

`zig build check` compiles the targets that support the selected linkage and runtime mode. Shared or runtime-loading checks omit WASI.

## Consumption

### Zig dependency

```sh
zig fetch --save git+https://github.com/CoffeeImpliesCode/cjson#v1.7.19
```

The module and artifact names are both `cjson`. Use `dep.artifact("cjson")` to link the artifact directly. Static builds provide `libcjson.a`; ELF dynamic builds provide `libcjson.so.1.7.19`.

### C dependency

Include `<cjson/cJSON.h>`. The install provides the `cjson.pc` pkg-config file. Shared Windows installs add `-DCJSON_IMPORT_SYMBOLS` to its `Cflags`.

## Licence

Copyright (c) 2009-2017 Dave Gamble and cJSON contributors

cJSON is distributed under the MIT licence in [`src/LICENSE`](src/LICENSE).
See [`NOTICE.md`](NOTICE.md) for third-party notices and
[`FORK-LICENSE.md`](FORK-LICENSE.md) for the fork's licence.
