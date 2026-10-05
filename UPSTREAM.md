# UPSTREAM.md — the pin, and what this fork changed

**Status of every statement in this file:** `SOURCE-CONFIRMED`. Every line
reference and every digest below was read out of the vendored tree or printed by
a command that ran while this package was written. The native build, test and
six-target compile gates have since been run — see [`CHANGELOG.md`](CHANGELOG.md)
section 2. Executing a cross-built binary has not.

## The pin

| Field | Value |
|---|---|
| Project | cJSON |
| Upstream | `https://github.com/DaveGamble/cJSON` |
| Tag | `v1.7.19` |
| Tag commit | `c859b25da02955fef659d658b8f324b5cde87be3` |
| Commit date | 2025-09-09T13:56:10Z (`Release 1.7.19 (#958)`) |
| Release tarball | `https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.19.tar.gz` |
| Tarball size | 356,247 bytes |
| **Tarball SHA-256** | **`7fa616e3046edfa7a28a32d5f9eacfd23f92900fe1f8ccd988c1662f30454562`** |
| Version in the source | 1.7.19, from `src/cJSON.h:82-84` (`CJSON_VERSION_MAJOR 1`, `CJSON_VERSION_MINOR 7`, `CJSON_VERSION_PATCH 19`) and `src/CMakeLists.txt:5` |
| Vendored tree | `src/`, 216 files, whole and unmodified |
| Licence | MIT, `src/LICENSE`: `Copyright (c) 2009-2017 Dave Gamble and cJSON contributors` |

The tarball digest appears in `UPSTREAM.sha256`'s header as well, and
`tools/check-provenance.sh` compares the two files so they cannot disagree.

`src/cJSON.c:120-122` makes the header the authority at compile time: the
version function is wrapped in

```c
#if (CJSON_VERSION_MAJOR != 1) || (CJSON_VERSION_MINOR != 7) || (CJSON_VERSION_PATCH != 19)
#error cJSON is not compatible with the current version
#endif
```

so a tree that claimed to be a different release would not compile at all. That
is why `build.zig` also refuses to configure when `build.zig.zon .version` and
the header disagree: three documents naming three releases is a state no gate
would catch on its own.

## How the source was obtained

1. The GitHub releases API named the latest release tag (`v1.7.19`,
   published 2025-09-09T13:58:05Z).
2. The tag ref was resolved through the API to the commit above, which is a
   lightweight tag: the object the ref points at is a commit, not an annotated
   tag object.
3. The tarball was fetched to approved scratch
   (`$HOST_SCRATCH_ROOT/scratch/foundation-libs`, after
   `source "$HOME/.local/lib/host-scratch.sh`), its digest computed, and the
   extracted tree copied into `src/` whole.

No build-time download exists: `build.zig` compiles `src/cJSON.c` and nothing
else reaches outside this repository.

## What is compiled, and what is not

**Compiled:** `src/cJSON.c`, and nothing else. That is upstream's own library
source list, not a choice this fork made to be small:
`src/CMakeLists.txt:101` is `set(SOURCES cJSON.c)` and `src/CMakeLists.txt:117`
adds exactly that one file to `add_library`. The whole library is one
translation unit and one header.

**Not compiled:** `src/cJSON_Utils.c`, upstream's JSON Patch and object-pointer
helpers. Upstream builds those into a *second* library target with its own
soname — `src/CMakeLists.txt:13` is `set(CJSON_UTILS_VERSION_SO 1)` and
`src/CMakeLists.txt:213-221` applies it to `${CJSON_UTILS_LIB}` — and this
package does not. The file is vendored, unmodified and uncompiled; a consumer
that wants those functions builds `cJSON_Utils.c` against `cJSON.h` itself, and
the digest of the file is in `UPSTREAM.sha256` either way.

The boundary matters in one direction a reader should be able to check: nothing
in this package publishes a `cJSONUtils_*` symbol, `zig/translate.h` does not
include `cJSON_Utils.h`, and therefore a provider this package loads cannot be
asked for one.

### The alternative, stated so the choice is reviewable

Compiling `cJSON_Utils.c` into the same archive would deliver more upstream code
for one link line, and it is defensible: the file only calls `cJSON_*` functions
that are already there. It is not what upstream does, and the difference is
visible to a consumer — under one name or the other, upstream never puts
`cJSONUtils_*` inside `libcjson`. The fork follows upstream.

## Build configuration, and where each flag comes from

No flag here is invented. Each is either upstream's default or a consequence of
one.

| Flag | Where it comes from | What it changes |
|---|---|---|
| `-DENABLE_LOCALES` | `src/CMakeLists.txt:273-276`, `option(ENABLE_LOCALES ... ON)` | `get_decimal_point()` asks `localeconv()` for the decimal separator (`src/cJSON.c:279-287`). Parsing substitutes it before `strtod` (`src/cJSON.c:366-376`) and printing puts `.` back (`src/cJSON.c:641-652`), so the JSON on the wire is locale-independent; the observable effect is that `localeconv()` is in the parse and print path. |
| `-fvisibility=hidden` | `src/CMakeLists.txt:86-90`, `ENABLE_PUBLIC_SYMBOLS` on by default | Makes `CJSON_PUBLIC` the only thing exported, through the macro the header defines for exactly this. |
| `-DCJSON_API_VISIBILITY` | same block | `src/cJSON.h:74-78` turns `CJSON_PUBLIC` into `__attribute__((visibility("default")))`. |
| `-DCJSON_EXPORT_SYMBOLS` | same block | `src/cJSON.h:63-69` turns it into `__declspec(dllexport)` on Windows. |
| *no* `-std=` | upstream sets no `C_STANDARD` and no `-std` | Pinning a dialect would be a second answer to a question upstream leaves to the compiler. |
| `-DCJSON_IMPORT_SYMBOLS` for consumers, in `Cflags` only for a shared install | `src/cJSON.h:67` | What a consumer of a DLL needs; false for an archive, so it is not in the static record. |

`ENABLE_HIDDEN_SYMBOLS` (`src/CMakeLists.txt:91-94`) is the alternative
configuration and is off upstream; this package does not offer it, because
switching it changes the ABI a provider must implement and nothing else in the
package depends on it.

## Shared-object version

Upstream's own numbers, not fork-invented ones: `src/CMakeLists.txt:12` is
`set(CJSON_VERSION_SO 1)` and `src/CMakeLists.txt:166-170` applies it as
`SOVERSION` with `VERSION "${PROJECT_VERSION}"`. Upstream's shared object is
therefore `libcjson.so.1.7.19` with soname `libcjson.so.1`, which is what
`-Dlinkage=dynamic` installs.

## System-library mode

**Withheld, and recorded as withheld rather than satisfied.**

There is no `b.systemIntegrationOption` in `build.zig`, so `-fsys=cjson` does
not exist for this package. The rule `WISDOM.md` W14 states is that system mode
must translate the headers it links — the real selected system headers, or an
explicitly required and verified identical header and ABI version — because
bundling a new release's header against an older installed library compiles and
then disagrees at run time. Applying it here:

* This host has **no installed cJSON** to compare against. That is an absence of
  evidence, not evidence of absence, and it is recorded as such: no query was
  run that would establish either way.
* Even with an installed library, the check would have to establish that its
  `cJSON` struct layout, its `cJSON_Version` string and its `CJSON_NESTING_LIMIT`
  match this tree's. `CJSON_NESTING_LIMIT` is a compile-time macro
  (`src/cJSON.h:134-144`), so two builds of the same version can reject documents
  at different depths under identical symbol names, and a header from one of them
  would misstate that.
* Offering the option without that comparison would advertise a mode that cannot
  be honoured honestly, which is the failure the rule exists to prevent.

`consumer/build.zig` records that a dependency still shares its parent's `Graph`
and therefore its `-fsys=` flags, so a future system mode in this package would
need no change there. That is a note for the next wave, not a working switch.

## Fixture corpus

`testdata/` is this fork's own corpus and is recorded by digest in
`UPSTREAM.sha256`. Two of its files have an outside origin, and one of them is
shared byte for byte with the `simdjson` package in this workspace, which is
what lets two independent JSON implementations be measured on the same bytes.

| Path | Origin | Provenance |
|---|---|---|
| `testdata/rfc8259/13-object.json` | RFC 8259 §13, first example | Transcribed verbatim from the RFC's plain text, `https://www.rfc-editor.org/rfc/rfc8259.txt`, SHA-256 `61a5378f4255c720beb2a4b4a63b29540147c140f36988bf086291989b4cd2d7`, lines 645-658 |
| `testdata/rfc8259/13-array.json` | RFC 8259 §13, second example | Same file, lines 681-702 |
| `testdata/rfc8259/13-value-string.json` | RFC 8259 §13, "three small JSON texts" | Same file, line 706: `"Hello world!"` |
| `testdata/rfc8259/13-value-number.json` | same | Same file, line 708: `42` |
| `testdata/rfc8259/13-value-boolean.json` | same | Same file, line 710: `true` |
| `testdata/large/twitter.json` | simdjson's own example corpus | Byte-identical copy of `jsonexamples/twitter.json` from simdjson 5.0.2; SHA-256 `30721e496a8d73cfc50658923c34eb2c0fbe15ee6835005e43ee624d8dedf200`, 631,515 bytes |
| `testdata/malformed/*.json` | this fork | Nine documents, each named for the rule it breaks; the expected outcome of each is recorded in `tests.zig` with the line references it was derived from |
| `testdata/values/*.json` | this fork | Number grammar, string escapes, duplicate names, nesting depths, and the two documents RFC 8259 forbids and this parser accepts |

**The RFC transcription rule, stated so it can be reproduced:** the RFC's text
formatting indents every preformatted line by exactly six spaces, and that
indent is page layout rather than content. Each file is the corresponding line
range with those six leading spaces removed and a single trailing newline added.
No other change was made, no line was reordered, and no byte inside a line was
touched.

**The two `values/` documents that are not conforming JSON, and why they are
here rather than in `malformed/`:**

* `values/leading-zero.json` is `{"a":01}`. RFC 8259 §6 forbids a leading zero.
  This parser accepts it and yields `1.0` (`src/cJSON.c:1399`, `:325-354`,
  `:378`), and that permissiveness is a fact a consumer has to know.
* `values/unescaped-control-character.json` contains a raw byte 0x01 inside a
  string. RFC 8259 §7 requires control characters to be escaped. This parser
  accepts it verbatim (`src/cJSON.c:867-873`) and re-emits it as `\u0001`
  (`src/cJSON.c:991-998`, `:1058`).

Neither is filed as a must-reject document, because neither is one.

## Package identity

| Field | Value | How it was derived |
|---|---|---|
| `build.zig.zon` `.name` | `cjson` | Matches the artifact, the module and the pkg-config `Name:` |
| `.version` | `1.7.19` | `src/cJSON.h:82-84`, `src/CMakeLists.txt:5` |
| `.fingerprint` | `0x807ca8b15ad818f6` | First eight bytes of `sha256("cjson 1.7.19")`, big-endian. Deterministic and recomputable rather than invented; `consumer/build.zig.zon`'s is `0xf6f887a8ffbf16a`, from `sha256("cjson_consumer 0.1.0")` |
| Artifact | `libcjson.a`, `libcjson.so.1.7.19` | `build.zig` names it; the `.so` name is upstream's `SOVERSION` plus upstream's version |
| Module | `dep.module("cjson")` | The one registered module |

## Re-sync procedure

This package tracks an archive release, not a branch, so a re-sync is a download
rather than a merge:

1. Fetch the release tarball to approved scratch, compute its SHA-256, and
   compare it with the release table above.
2. Replace `src/` with the extracted tree, whole. Nothing is patched, so there
   is no patch file to re-apply and no pristine import to diff against.
3. Read the new `src/cJSON.h:82-84` and `src/CMakeLists.txt` version, and the
   new `src/CMakeLists.txt:12` `CJSON_VERSION_SO`.
4. Update `build.zig`'s `upstream_version`, `abi_version` and the header comment
   in `zig/translate.h`; update `build.zig.zon .version` and its comment.
5. Regenerate `UPSTREAM.sha256` and run `tools/check-provenance.sh`.
6. Re-read every fixture the new release changes the behaviour of — the print
   table in `tests.zig` is upstream's own, so a formatter change shows up there
   first.
7. Add one numbered `CHANGELOG.md` entry and one `FORK-NOTES.md` record.

## Remote hygiene

Upstream is `https://github.com/DaveGamble/cJSON`, and this repository is a
downstream of it, not a fork of the account: it carries a different name, a
different licence file layout and this fork's own build system. A downstream
must never be created with `gh repo fork` plus a visibility change; the remote
configuration belongs to the driver, and this package records no remote of its
own.