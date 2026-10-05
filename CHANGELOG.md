# CHANGELOG.md — cJSON Zig package

Numbered. Every entry is a change to *this package*; upstream's own release
history is in `src/CHANGELOG.md`, preserved as it was shipped.

**Status.** Section 1 was written before anything here was compiled, and every
statement in it that describes behaviour is `SOURCE-CONFIRMED` — read out of
`src/` or out of this repository's own files. Section 2 records the first build
under Zig 0.16.0, the gates it ran and what those gates returned.

---

## 1. Initial package: cJSON 1.7.19

**Date:** 2026-10-05
**Upstream pin:** tag `v1.7.19`, tag commit `c859b25da02955fef659d658b8f324b5cde87be3`,
release tarball sha256 `7fa616e3046edfa7a28a32d5f9eacfd23f92900fe1f8ccd988c1662f30454562`.

### Added — native source

- `src/`: the complete cJSON 1.7.19 release tree, 216 files, whole and
  unmodified. Nothing excluded, nothing edited, every file digest-recorded in
  `UPSTREAM.sha256`. Includes upstream's complete test suite, the vendored Unity
  test framework, the vendored JSON Patch corpus, the fuzzing harnesses and
  upstream's own build files and documentation.
- `README.upstream.md`: `src/README.md`, byte for byte.

### Added — build graph

- `build.zig` compiling `src/cJSON.c` — upstream's own library source list
  (`src/CMakeLists.txt:101`) — with no CMake, no make, no configure step and no
  download. Steps: default (install), `test`, `smoke`, `check`.
- Options: `-Dlinkage=static|dynamic`, `-Druntime=true|false`, `-Dtarget`.
- Every compile flag taken from upstream's own default configuration:
  `-DENABLE_LOCALES`, `-fvisibility=hidden`, `-DCJSON_API_VISIBILITY`,
  `-DCJSON_EXPORT_SYMBOLS`. No `-std=` is pinned, because upstream pins none.
- The shared object is `libcjson.so.1.7.19` with soname `libcjson.so.1`, from
  upstream's own `CJSON_VERSION_SO` (`src/CMakeLists.txt:12`) rather than a
  fork-invented ABI number.
- Install closure: `libcjson.*`, `include/cjson/cJSON.h`,
  `lib/pkgconfig/cjson.pc`, and `share/licenses/cjson/` with both grants.
- `build.zig.zon`: `.name = .cjson`, `.version = "1.7.19"` cross-checked against
  `src/cJSON.h:82-84` at configure time, `.fingerprint` derived deterministically
  from `sha256("cjson 1.7.19")`, no dependencies, and an explicit `.paths` list.

### Added — Zig surface

- `zig/translate.h`, which includes `<cJSON.h>` whole and defines no macro of its
  own, so the translation cannot disagree with the real header by omission.
- `zig/root.zig`: `parse`, `parseBytes`, `parseErrorOffset`, `print`,
  `printInto`, `freePrinted`, `version`, `createObject`/`createArray`/
  `createString`/`createNumber`/`createBool`/`createNull`, `duplicate`, `put`,
  `append`, `insertAt`, `detachField`, `deleteField`, `replaceField`, and the
  `Type`, `Sensitivity`, `Format`, `ParseOptions`, `Document`, `Owned` and
  `Borrowed` types.
- Ownership is a type: `Borrowed` has no `deinit`, so no member of a document can
  be released through this API.
- The error taxonomy is cut at what this package checked, because cJSON's header
  declares no error enumeration and this API does not invent one.

### Added — runtime loading

- `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`,
  `runtime/sync.h`: copied from this workspace's shared runtime core, byte for
  byte apart from the SPDX line and the header guard.
- `runtime/graph.zig`: the wiring, the `cjson_rt` synchronization prefix, and
  the classification of what is routed. Nothing is classified as the C library's
  or as optional, because the translated header's only include is `<stddef.h>`
  (`src/cJSON.h:86`), which declares no function.
- `runtime/library.zig`: the load-time descriptor and four observable checks —
  version family, allocator round trip, struct-layout and numeric-width
  round trip, and error-channel position.

### Added — tests, example, consumer

- `tests.zig`: behavioural tests over the RFC 8259 §13 fixtures, upstream's own
  printed-number table (`src/tests/print_number.c:65-101`), upstream's error
  offsets for eight malformed documents, the depth limit, a 631,515-byte
  real-world document, ownership transitions, mutation, comparison and printing.
- `smoke.zig`: one end-to-end pass that checks its own answers and prints them.
- `consumer/`: a separate package depending on this one by relative path,
  importing `dep.module("cjson")` and nothing else, and asserting RFC 8259's own
  numbers.
- `testdata/`: RFC 8259 §13 fixtures, this fork's malformed and value documents,
  and simdjson's `twitter.json` copied byte for byte.

### Added — packaging and gates

- `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`,
  `cross-test.profile.sh`, `.gitignore`, `.github/workflows/verify.yml`,
  `tools/check-provenance.sh`, `UPSTREAM.sha256`.

### Added — records

- `UPSTREAM.md` (pin, flag derivations, fixture provenance, package identity,
  re-sync procedure, system-mode reasoning), `NOTICE.md` (per-file licence
  inventory), `FORK-LICENSE.md`, `README.md`, `README.zig.md`, `FORK-NOTES.md`.

### Decided, and recorded as decided

- **No system-library mode.** Recorded as *withheld*, not satisfied. See
  `UPSTREAM.md`, "System-library mode".
- **`cJSON_Utils.c` is not compiled.** Upstream builds it as a separate target
  with its own soname; nothing here publishes a `cJSONUtils_*` symbol.
- **`item->type` is never named.** `type` is a Zig keyword and a translation of
  `src/cJSON.h:112` has to rename it, so the facade asks upstream through the
  `cJSON_Is*` functions instead.
- **`valueint` is not exposed.** It is a saturating `int` copy of the same number
  (`src/cJSON.c:388-400`) and would be a silent wrong answer.

### Known open items

None outstanding inside the package: every question that could not be answered
from source is listed in `FORK-NOTES.md`, "Open questions", rather than guessed
at in code.

### Gates still to be run by the driver

```
zig build test -Doptimize=ReleaseSafe
zig build run             # from consumer/
cross-test                # from the package root
```

---

## 2. First build under Zig 0.16.0

**Date:** 2026-10-05

The tree recorded in section 1 had never been compiled. This entry is the
repair that made it build, and the gates that were run afterwards.

### Fixed — the Zig surface

- `zig/root.zig` published `put`, `append`, `insertAt`, `detachField`,
  `deleteField` and `replaceField` as module-level functions, while
  `README.zig.md`, `smoke.zig` and `tests.zig` all call them as methods on
  `Borrowed`. The six are now methods on `Borrowed` and the free functions are
  gone; nothing called them in the old spelling.
- `zig/root.zig`'s `parse` passed a `?[*:0]const u8` to `cJSON_ParseWithOpts`,
  whose translated second parameter is `[*c][*c]const u8` (`const char **`).
  A NUL-terminated pointer and a C pointer are different types, because their
  sentinels differ; the local is now `[*c]const u8`, and `&end` coerces into the
  parameter.

### Fixed — the tests

Six expectations did not describe what the compiled upstream code does. Each was
corrected against a derivation from `src/cJSON.c` or against the built library,
not against the observed value alone. No assertion was removed.

- `testdata/rfc8259/13-object.json` has one top-level member, `Image`. The count
  is now asserted as 1, and the nested object's own six members are asserted too.
- `print_number` keeps the 15-digit form of the largest double, because
  `compare_double`'s tolerance accepts it (`src/cJSON.c:584-588`, `:618-625`):
  `1.7976931348623157e308` prints as `1.79769313486232e+308`. `README.zig.md`
  carried the same claim and now states this one.
- `{'a':'b'}` is refused at offset 2, not 0. The value is an object, so
  `parse_value` takes its `{` branch and `parse_object` asks `parse_string` for
  the name at index 1; the failure path records one past that.
- `{"a":"b}` is refused at offset 6, not 7. The value string scans off the end
  looking for a closing quote, and the offset recorded is one past its own
  opening one.
- The nesting fixtures are `depth` objects named `a` around one object holding
  `leaf`, so the walk needs one more step to reach the member the assertions are
  about.
- The comparison test's `sum` document held `0.1`. The binary64 sum of `0.1` and
  `0.2` is `0.30000000000000004`, and the assertion that it compares equal to
  `0.3` could not have held for `0.1` and `0.3`. The bit patterns are now taken
  from parsed documents rather than comptime literals, because Zig evaluates a
  comptime `0.1 + 0.2` in wider arithmetic where it rounds to the same binary64
  as `0.3`.

### Fixed — the records

- `tools/check-provenance.sh` exited 1: `README.md` and `UPSTREAM.md` broke the
  cJSON copyright notice across a line, so the gate could not find the string it
  requires in the records. Both carry it on one line now.
- This file, `README.md`, `FORK-NOTES.md` and `UPSTREAM.md` each stated that
  nothing here had been built. Each states what has run.

### Gates run

Zig 0.16.0, host `x86_64-linux-gnu`, Debug:

```
zig build                    # 13/13 steps, exit 0
zig build test               # 24/24 tests passed, exit 0
zig build smoke              # ran, exit 0
zig build check              # 32/32 steps, all six required targets, exit 0
zig build -Dlinkage=dynamic  # 13/13 steps, exit 0
zig build -Druntime=true     # 14/14 steps, exit 0
tools/check-provenance.sh    # exit 0
```

`zig build check` compiles x86_64-linux-gnu, aarch64-linux-gnu, aarch64-macos,
x86_64-windows-gnu, riscv64-linux-gnu and wasm32-wasi. None of those binaries
was executed.

### Gates not run

`zig build test -Doptimize=ReleaseSafe`, `zig build run` from `consumer/`,
`cross-test`, the Nix expressions and CI.