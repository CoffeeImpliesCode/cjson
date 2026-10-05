# NOTICE.md — per-file licence inventory

**Status:** `SOURCE-CONFIRMED`. Every line reference below was read out of the
vendored tree at the pinned tag; no file under `src/` was modified. Nothing here
is a summary label: a tree is licensed file by file, and this release is not one
licence.

A private downstream repository removes no obligation. Everything upstream ships
with its notice intact, in its own file, at its own path.

## The rule this inventory follows

Each compiled file, each retained file, and each vendored third-party tree is
listed with the term that governs *that* file and where its notice lives. Where
a file carries no notice of its own, that is said rather than inherited silently.
Where a notice refers to another file, this record says whether that file is
present.

## 1. The compiled core

| File | Term | Notice |
|---|---|---|
| `src/cJSON.c` | MIT | `src/cJSON.c:1-21`: `Copyright (c) 2009-2017 Dave Gamble and cJSON contributors`, with the permission grant, the notice condition and the warranty disclaimer in full. |
| `src/cJSON.h` | MIT | `src/cJSON.h:1-21`: the same notice, byte for byte. |

`src/cJSON.c` is the only compiled file in this package (`src/CMakeLists.txt:101`,
`set(SOURCES cJSON.c)`), and both of them are cJSON's own MIT text. The full text
is also a standalone file, `src/LICENSE`, which is the copy this package installs
as `share/licenses/cjson/LICENSE.cJSON`.

## 2. The vendored source this package does not compile

| File | Term | Notice |
|---|---|---|
| `src/cJSON_Utils.c` | MIT | `src/cJSON_Utils.c:1-21`: `Copyright (c) 2009-2017 Dave Gamble and cJSON contributors`. Upstream builds it as a separate library target; see UPSTREAM.md. |
| `src/cJSON_Utils.h` | MIT | `src/cJSON_Utils.h:1-21`: the same notice. |
| `src/test.c` | MIT | `src/test.c:1-21`: the same notice. |
| `src/tests/minify_tests.c` | MIT | `Copyright (c) 2009-2019 Dave Gamble and cJSON contributors` — a **different year range** from the library's `2009-2017`, in the file's own header. Recorded separately rather than folded into the family above, because a per-file inventory that smoothed this over would be wrong about one file. |
| `src/fuzzing/afl.c` | MIT | `src/fuzzing/afl.c:1-20`: `Copyright (c) 2009-2017 Dave Gamble and cJSON contributors`. It is a shim that includes AFL++'s header, which upstream does not vendor; nothing from AFL++ is in this tree. |
| `src/fuzzing/*.c`, `src/fuzzing/*.sh`, `src/fuzzing/CMakeLists.txt`, `src/fuzzing/json.dict`, `src/fuzzing/inputs/*` | MIT | `src/fuzzing/fuzz_main.c:1-21` and `src/fuzzing/cjson_read_fuzzer.c:1-21` carry the cJSON notice; the shell scripts, the CMake file, the dictionary and the input corpus carry none of their own and inherit the project's terms from the files beside them. |
| `src/library_config/*` | MIT | No per-file notice. These are documentation files describing the build configuration; the directory ships inside cJSON's MIT-licensed release. |
| `src/CMakeLists.txt`, `src/Makefile` | MIT | No per-file notice. Build files, retained so the build definition this package replaces is visible in the tree. |
| `src/README.md`, `src/CHANGELOG.md`, `src/CONTRIBUTORS.md`, `src/SECURITY.md`, `src/appveyor.yml`, `src/valgrind.supp` | MIT | `src/README.md` and `src/CHANGELOG.md` carry the cJSON notice in their text; the others carry none of their own. |

## 3. The vendored Unity test framework

`src/tests/unity/` is ThrowTheSwitch's Unity, vendored by cJSON for its own test
suite. It is **not** covered by cJSON's notice, and it is not cJSON's code.

| Fact | Value |
|---|---|
| Term | MIT |
| Copyright holders | Mike Karlesky, Mark VanderVoord, Greg Williams |
| Licence text | `src/tests/unity/docs/license.txt`, present in this release |
| What the sources refer to | `src/tests/unity/src/unity.c:1-5` says `[Released under MIT License. Please refer to license.txt for details]`, and the file that name refers to is `src/tests/unity/docs/license.txt`. It ships; `tools/check-provenance.sh` checks that it does. |
| Files carrying the notice | 32 files carry a Unity copyright line; the source headers, `README.md`, and the `extras/` and `auto/` trees. |
| Files with **no** notice | The Unity sources that carry only the `license.txt` reference line, plus the release notes, IDE extras and target files. Nothing in `src/tests/unity/` is removed for that reason. |

Two contributors inside that tree have their own lines, and both are recorded
because both are in files this package ships:

| File | Notice |
|---|---|
| `src/tests/unity/extras/fixture/src/unity_fixture.c` and the rest of `src/tests/unity/extras/fixture/` | `Copyright (c) 2010 James Grenning and Contributed to Unity Project` |
| `src/tests/unity/auto/unity_test_summary.py` | `Copyright (c) 2015 Alexander Mueller / XelaRellum@web.de` |
| `src/tests/unity/docs/UnityGettingStartedGuide.md` | Carries the Unity copyright line in the quoted header it documents. |

## 4. The vendored JSON Patch corpus

`src/tests/json-patch-tests/` is the `json-patch/json-patch-tests` suite, which
cJSON vendors to test `cJSON_Utils.c`.

| Fact | Value |
|---|---|
| Term | **Apache-2.0**, declared by `src/tests/json-patch-tests/package.json` (`"license": "Apache-2.0"`) |
| Copyright | `Copyright 2014 The Authors`, in `src/tests/json-patch-tests/README.md` |
| The JSON files themselves | `tests.json`, `spec_tests.json`, `cjson-utils-tests.json` carry **no** notice of their own. The corpus files are derived from the RFC 6902 examples and from contributor submissions; their terms are the ones recorded above, in the files that state them. |
| Upstream's Apache-2.0 text | Not vendored inside this corpus directory. This is a fact about what upstream ships, recorded rather than worked around: the licence is declared by name in `package.json`, and this fork's `FORK-LICENSE.md` does not restate or replace it. |

This is the one place in the tree where a single label — "MIT" — would be
false, and it is why the inventory is per file.

## 5. This fork's own files

Everything outside `src/` and `testdata/` is authored by this fork and is
licensed under `FORK-LICENSE.md`: MIT, matching cJSON's own terms, with the
owner-authorized grant for fork additions recorded there. No upstream author is
credited for them.

| File | Term |
|---|---|
| `build.zig`, `build.zig.zon`, `zig/root.zig`, `zig/translate.h`, `tests.zig`, `smoke.zig` | `FORK-LICENSE.md` (MIT) |
| `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` | `FORK-LICENSE.md` (MIT). Copied from this workspace's shared runtime core, not written for this package; see `FORK-NOTES.md`. |
| `runtime/graph.zig`, `runtime/library.zig` | `FORK-LICENSE.md` (MIT), written for this package. |
| `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` | `FORK-LICENSE.md` (MIT) |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`, `cross-test.profile.sh`, `.gitignore`, `.github/workflows/verify.yml`, `tools/check-provenance.sh` | `FORK-LICENSE.md` (MIT) |
| `README.md`, `README.zig.md`, `UPSTREAM.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md`, `UPSTREAM.sha256`, `README.upstream.md` | `FORK-LICENSE.md` (MIT). `README.upstream.md` is a byte-identical copy of `src/README.md` and stays under cJSON's MIT terms as well as this record's. |

## 6. The fixture corpus

`testdata/` is authored by this fork except for two files with an outside
origin, and both are named rather than assumed:

| Path | Term | Origin |
|---|---|---|
| `testdata/rfc8259/*` | This fork's transcription | RFC 8259 (December 2017) is an IETF Standards Track document published by the RFC Editor, which places no licence restriction on its text. The five files are transcribed from it; the digests are in `UPSTREAM.sha256` and the transcription rule is in `UPSTREAM.md`. |
| `testdata/large/twitter.json` | This fork's copy of simdjson's example corpus | A byte-identical copy of `jsonexamples/twitter.json` from simdjson 5.0.2, which is dual-licensed Apache-2.0 or MIT at the licencee's option (`src/LICENSE`, `src/LICENSE-MIT` in that project). This fork records **MIT**, and nothing in this package modifies the file or depends on its licence terms beyond retaining the notice. |
| `testdata/malformed/*`, `testdata/values/*` | `FORK-LICENSE.md` (MIT) | Authored here. |

## What an installed tree carries

`zig build` installs, under `share/licenses/cjson/`:

| Installed name | Source |
|---|---|
| `LICENSE.cJSON` | `src/LICENSE` — cJSON's own MIT text, installed under a distinct name because it is a distinct grant from `FORK-LICENSE.md` |
| `NOTICE.md` | this file |
| `FORK-LICENSE.md` | the fork's grant for its own files |
| `UPSTREAM.md` | the pin, the deviations and the fixture provenance |
| `README.upstream.md` | `src/README.md`, byte for byte |

The vendored Unity and JSON Patch material is inside the installed *source*
tree (`src/` ships whole, including its licences at `src/tests/unity/docs/
license.txt` and the corpus's own `package.json`), so a consumer who needs those
terms can find them at their upstream paths rather than in a flattened list.