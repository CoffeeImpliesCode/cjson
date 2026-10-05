# cJSON for Zig 0.16

cJSON 1.7.19 — "An ultra-lightweight JSON parser in ANSI C" — built from
vendored source by Zig 0.16, with a typed Zig facade, an optional runtime-loading
route, and both static and shared delivery.

```zig
const cjson = @import("cjson");

var doc = try cjson.parse("{\"name\":\"cjson\",\"tags\":[\"parse\",\"print\"]}", .{});
defer doc.deinit();

const tags = doc.rootValue().field("tags", .case_sensitive).?;
try std.testing.expectEqualStrings("parse", tags.at(0).?.stringValue().?);
```

Upstream: `https://github.com/DaveGamble/cJSON`, tag `v1.7.19`, tag commit
`c859b25da02955fef659d658b8f324b5cde87be3`. Upstream's own README is preserved
byte for byte as [`README.upstream.md`](README.upstream.md).

**This package has been built natively under Zig 0.16.0.** `zig build`,
`zig build test`, `zig build smoke`, `zig build check` and
`tools/check-provenance.sh` all exit zero; the exact results are recorded in
[`CHANGELOG.md`](CHANGELOG.md) section 2. Every behavioural statement below is
still `SOURCE-CONFIRMED` — read out of the vendored source or out of a record —
and no cross-built binary has been executed.

---

## 1. Native-source deviations

**There are none.** `src/` is the cJSON 1.7.19 release tree, whole and
unmodified: 216 files, every one of them digest-recorded in
[`UPSTREAM.sha256`](UPSTREAM.sha256), including the complete upstream test
suite, the vendored Unity test framework, the vendored JSON Patch corpus, the
fuzzing harnesses, upstream's CMakeLists and Makefile, and upstream's own
README, CHANGELOG, CONTRIBUTORS and SECURITY policy.

Nothing was patched, nothing was re-entered, nothing was reformatted, and no
file was dropped — not even the ones this package does not need. There is no
patch file to re-apply and no pristine import to diff against, because there is
nothing to diff.

The one boundary a reader should be able to check is what gets *compiled*:
`src/cJSON.c` alone, which is upstream's own library source list
(`src/CMakeLists.txt:101`, `set(SOURCES cJSON.c)`). `src/cJSON_Utils.c` is
vendored, unmodified and uncompiled, because upstream builds it into a different
library target with its own soname
([`UPSTREAM.md`](UPSTREAM.md), "What is compiled, and what is not"). Nothing in
this package publishes a `cJSONUtils_*` symbol.

## 2. Native-build deviations and history

Upstream builds with CMake or with a Makefile. This package builds with neither:
`build.zig` compiles `src/cJSON.c` directly, and no CMake, no `make`, no
configure step and no download runs at build time.

Every compile flag this package uses, and where each comes from:

| Flag | Source | Effect |
|---|---|---|
| `-DENABLE_LOCALES` | `src/CMakeLists.txt:273-276`, default **ON** upstream | `get_decimal_point()` consults `localeconv()` (`src/cJSON.c:279-287`). Parsing substitutes the locale's separator before `strtod` (`:366-376`) and printing puts `.` back (`:641-652`), so the JSON on the wire is locale-independent. |
| `-fvisibility=hidden` | `src/CMakeLists.txt:86-90`, `ENABLE_PUBLIC_SYMBOLS` **On** upstream | Only `CJSON_PUBLIC` is exported. |
| `-DCJSON_API_VISIBILITY` | same block | `CJSON_PUBLIC` becomes `visibility("default")` off Windows (`src/cJSON.h:74-78`). |
| `-DCJSON_EXPORT_SYMBOLS` | same block | `CJSON_PUBLIC` becomes `__declspec(dllexport)` on Windows (`src/cJSON.h:63-69`). |
| *no* `-std=` | upstream sets none | Pinning a dialect would answer a question upstream leaves to the compiler. |

The export surface is therefore decided at compile time through the header's own
documented mechanism (`src/cJSON.h:37-53`), which is why this package adds no
version script and no generated module definition.

What the build adds around those flags:

* `-Dlinkage=static` (default) installs `libcjson.a`; `-Dlinkage=dynamic`
  installs `libcjson.so.1.7.19` with `libcjson.so.1` and `libcjson.so` beside
  it. The version is **upstream's**, not invented: `src/CMakeLists.txt:12` is
  `set(CJSON_VERSION_SO 1)`, applied at `:166-170` alongside
  `VERSION "${PROJECT_VERSION}"`.
* `-Druntime=true` resolves the library's entry points at run time through one
  process-lifetime table instead of linking them. The facade keeps the same
  types and the same public surface; a caller names a provider with an explicit
  `load(source)`.
* `zig build check` compiles the library, the translated header, the facade, the
  tests and the example for six targets without running any of them.
* `zig build install` publishes `include/cjson/cJSON.h` — the directory upstream
  installs into (`src/CMakeLists.txt`, `.../cjson`) — plus
  `lib/pkgconfig/cjson.pc` and the licence material.

**Not provided:** there is no system-library mode. `-fsys=cjson` does not exist
for this package, and that is recorded as *withheld*, not satisfied. The rule
([`WISDOM.md`](../../foundation/WISDOM.md) W14) requires system mode to translate
the headers it links, because a new release's header against an older installed
library compiles and then disagrees at run time; no installed cJSON was
available here to compare against, and `CJSON_NESTING_LIMIT` is a compile-time
macro (`src/cJSON.h:134-144`) that two builds of the same version can set
differently. The reasoning is in [`UPSTREAM.md`](UPSTREAM.md).

### History

This package is new in this workspace: cJSON was not among the earlier forks.
Its first record is `CHANGELOG.md` entry 1, and there is no earlier native-build
deviation to preserve.

## 3. Support matrix

Targets this package's own `check` step compiles, all six, none skipped:

| Target | Note |
|---|---|
| `x86_64-linux-gnu` | |
| `aarch64-linux-gnu` | |
| `aarch64-macos-none` | `ld64` exports every global symbol by default and this build has no first-class way to narrow it, so a macOS shared object carries a wider export table than the ELF one. The C ABI a consumer calls is identical. |
| `x86_64-windows-gnu` | `CJSON_EXPORT_SYMBOLS` gives the DLL a real export table through the header itself. |
| `riscv64-linux-gnu` | |
| `wasm32-wasi` | No dynamic linker, so `-Dlinkage=dynamic` is **refused** for this cell with a message naming the target. It is not downgraded to an archive, and `zig build check` with no flag still compiles it, because the default is `static`. |

The wider 53-platform matrix is run by `cross-test` from the package root, using
[`cross-test.profile.sh`](cross-test.profile.sh) for its settings. It is not a
GitHub job here: `cross-test` is a host-local tool with its own runner detection
and scratch policy, so a job that invoked it on a runner would fail for a reason
that has nothing to do with this package. A platform with no runner is recorded
as `build_only` coverage — compiled, never executed, never a pass.

**Status of this table:** the target *list* is what the build graph contains and
`zig build check` compiles all six cells.

**Status of the 53-platform matrix: `OBSERVED`, one cell red.** Run from the
package root on 2026-10-05 with Zig 0.16.0, run id
`20261005-191618-17929-17203`, harness exit code 1, all 53 cells present:

| Outcome | Cells | What it means |
|---|---|---|
| `pass` | 19 | Built and executed, 24 of 24 tests each |
| `build_only` | 33 | Compiled; no runner on this host, so never executed and **not** a pass |
| `runtime_fail` | 1 | `armeb-linux`: built, ran, 23 of 24, one test failed |

The `armeb-linux` failure is not this package's code and is recorded as boundary
2.6 in [`FORK-NOTES.md`](FORK-NOTES.md): the big-endian ARM VFP variadic call
boundary delivers a `double` with its two 32-bit halves exchanged, so
`sprintf("%1.15g", 0.123)` receives the wrong argument. It reproduces in a C
program with no cJSON in it, and the test's comparison is left byte for byte.

## 4. Consuming it

### From Zig, by dependency

```zig
// build.zig.zon
.dependencies = .{
    .cjson = .{ .path = "../cjson" },
},

// build.zig
const cjson_dep = b.dependency("cjson", .{ .target = target, .optimize = optimize });
exe_mod.addImport("cjson", cjson_dep.module("cjson"));
```

`dep.module("cjson")` carries the translated header as `cjson.c` and the typed
facade as `cjson`'s own declarations. `dep.artifact("cjson")` is the same name
and gives you `libcjson.a` or `libcjson.so.1.7.19` to link by hand.

[`consumer/`](consumer/) is a working example of exactly that: a separate
package with its own manifest, depending on this one by relative path, printing
RFC 8259's own numbers and exiting non-zero if they do not come out.

### From C

```c
#include <cjson/cJSON.h>

cJSON *doc = cJSON_Parse("{\"a\":1}");
/* ... */
cJSON_Delete(doc);
```

The installed header is at `include/cjson/cJSON.h` because that is where
upstream installs it. A shared install carries `-DCJSON_IMPORT_SYMBOLS` in
`cjson.pc`'s `Cflags`, which is what turns `CJSON_PUBLIC` into `dllimport` on
Windows; a static install carries nothing, because upstream's own default for a
static build needs nothing.

### The API

[`README.zig.md`](README.zig.md) is the API documentation: every public type,
method and error, with the upstream line each behaviour comes from, the two
parse entry points, the ownership rules, the error taxonomy and the
documented-divergence list.

### Runtime loading

With `-Druntime=true` the module links no archive. A caller names a provider
once:

```zig
if (cjson.runtime_loaded) {
    cjson.load(.{ .path = "/path/to/libcjson.so.1.7.19" }) catch |err| return err;
}
```

One process-lifetime table per module, explicit provider selection (`.path` or
`.system`), **no fallback** to another library, atomic publication, an explicit
retry after a failed attempt, and an ordinary pre-initialization panic in every
optimization mode. In a linked build `runtime_loaded` is `false` and `load`
stops the program with a message saying so rather than pretending to load
something.

The provider must pass the checks in
[`runtime/library.zig`](runtime/library.zig): `cJSON_Version()` must report
`1.7.19`, an object must be creatable, a member must be findable by its exact
name and report back the same `double`, and a failed parse must leave an error
position inside the buffer that was parsed.

## 5. Fixtures and what the tests prove

The primary fixture is independent of cJSON:

* `testdata/rfc8259/` — the section 13 examples of **RFC 8259** (Bray,
  December 2017), transcribed verbatim. The expected values in those tests are
  the ones the RFC prints, so agreeing with them is agreeing with the
  specification.
* Upstream's own printed-number table, `src/tests/print_number.c:65-101`, is the
  oracle for the formatter. That is interoperability with the reference
  implementation's recorded expectations.
* `testdata/large/twitter.json` — simdjson's own example corpus, 631,515 bytes,
  byte-identical across this workspace's two JSON packages. The tests assert
  counts and fields read out of it, including the one place where a `double`
  visibly loses digits that the string member keeps.
* `testdata/malformed/` and `testdata/values/` — this fork's own documents, each
  with its expected outcome and the line references it was derived from.

Every one of those digests is in `UPSTREAM.sha256`, and
`tools/check-provenance.sh` checks that the shared files still match what the
sibling package records.

## 6. Licensing

Two grants, not one. Upstream's is MIT (`src/LICENSE`, and the notice in every
one of its own source files: `Copyright (c) 2009-2017 Dave Gamble and cJSON contributors`).
This fork's own files are MIT under [`FORK-LICENSE.md`](FORK-LICENSE.md), which
records the owner's authorization for fork additions and credits no upstream
author for them.

The tree is **not** uniformly MIT, and [`NOTICE.md`](NOTICE.md) is the per-file
inventory that says why: the vendored Unity test framework is MIT with its own
copyright holders, the vendored JSON Patch corpus is **Apache-2.0** by its own
`package.json`, and one upstream test file carries a different year range
(`2009-2019`) from the library's. `zig build` installs both grants under
`share/licenses/cjson/`.

## 7. Provenance

[`UPSTREAM.md`](UPSTREAM.md) is the pin, the derivation of every flag, the
fixture provenance, the package identity and the re-sync procedure.
[`UPSTREAM.sha256`](UPSTREAM.sha256) records every byte this package ships from
upstream and every fixture byte its tests read, plus the release tarball's own
digest. [`FORK-NOTES.md`](FORK-NOTES.md) records the decisions, the boundaries
and the open questions, and [`CHANGELOG.md`](CHANGELOG.md) the numbered changes.

Verify the source without a compiler:

```sh
sha256sum -c UPSTREAM.sha256
tools/check-provenance.sh
```