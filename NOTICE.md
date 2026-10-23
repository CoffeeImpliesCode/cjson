# Notices

| Paths | Licence and attribution |
|---|---|
| `src/cJSON.c`, `src/cJSON.h` | MIT; `Copyright (c) 2009-2017 Dave Gamble and cJSON contributors`. Both carry the same notice; its full text is in `src/LICENSE`, installed as `share/licenses/cjson/LICENSE.cJSON`. |
| `src/cJSON_Utils.c`, `src/cJSON_Utils.h`, `src/test.c` | MIT; same cJSON notice. |
| `src/tests/minify_tests.c` | MIT; `Copyright (c) 2009-2019 Dave Gamble and cJSON contributors`. |
| `src/fuzzing/*.c` | MIT; cJSON notice. `afl.c` includes an AFL++ header; no AFL++ code is vendored. |
| `src/fuzzing/*.sh`, `src/fuzzing/CMakeLists.txt`, `src/fuzzing/json.dict`, `src/fuzzing/inputs/*`, `src/library_config/*`, `src/CMakeLists.txt`, `src/Makefile` | MIT; no per-file notice. |
| `src/README.md`, `src/CHANGELOG.md` | MIT; cJSON notice in the text. |
| `src/CONTRIBUTORS.md`, `src/SECURITY.md`, `src/valgrind.supp` | MIT; no per-file notice. |
| `src/tests/unity/**` | Unity MIT; copyright Mike Karlesky, Mark VanderVoord, and Greg Williams. `src/tests/unity/docs/license.txt` ships and is referenced by `unity.c`. 32 files carry Unity copyright lines: source headers, `README.md`, `extras/`, and `auto/`. Unity sources with only the license reference, release notes, IDE extras, and target files have no notice. |
| `src/tests/unity/extras/fixture/**` | `Copyright (c) 2010 James Grenning and Contributed to Unity Project`. |
| `src/tests/unity/auto/unity_test_summary.py` | `Copyright (c) 2015 Alexander Mueller / XelaRellum@web.de`. |
| `src/tests/unity/docs/UnityGettingStartedGuide.md` | Unity copyright line in its quoted header. |
| `src/tests/json-patch-tests/**` | Apache-2.0, declared in `package.json`; `README.md` says `Copyright 2014 The Authors`. The JSON corpus files have no individual notice and derive from RFC 6902 examples and contributor submissions. The Apache-2.0 text is absent; `FORK-LICENSE.md` does not replace it. |
| Fork-authored files outside `src/` and `testdata/` | `FORK-LICENSE.md` (MIT), matching cJSON's terms; the owner-authorized grant for fork additions is recorded there. No upstream author is credited for these files. |
| `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` | `FORK-LICENSE.md` (MIT); copied from this workspace's shared runtime core. |
| `build.zig`, `build.zig.zon`, `zig/root.zig`, `zig/translate.h`, `tests.zig`, `smoke.zig`, `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig`, `runtime/graph.zig`, `runtime/library.zig` | `FORK-LICENSE.md` (MIT). |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`, `cross-test.profile.sh`, `.gitignore`, `tools/check-provenance.sh` | `FORK-LICENSE.md` (MIT). |
| `README.md`, `README.zig.md`, `UPSTREAM.md`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md`, `UPSTREAM.sha256`, `README.upstream.md` | `FORK-LICENSE.md` (MIT). `README.upstream.md` is byte-identical to `src/README.md` and also carries cJSON's MIT terms. |
| `testdata/rfc8259/*` | Five transcriptions from RFC 8259 (December 2017); the RFC Editor places no licence restriction on its text. |
| `testdata/large/twitter.json` | Byte-identical to simdjson 5.0.2's `jsonexamples/twitter.json`; dual-licensed Apache-2.0 or MIT, recorded here under MIT. |
| `testdata/malformed/*`, `testdata/values/*` | Fork-authored; `FORK-LICENSE.md` (MIT). |

`zig build` installs `LICENSE.cJSON` from `src/LICENSE`, `NOTICE.md`, `FORK-LICENSE.md`, `UPSTREAM.md`, and `README.upstream.md` under `share/licenses/cjson/`. The installed `src/` tree includes Unity's `license.txt` and the JSON Patch `package.json` at their upstream paths.
