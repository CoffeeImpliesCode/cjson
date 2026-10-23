# FORK-LICENSE.md

**SPDX-License-Identifier: MIT**

This grant covers the listed files, not upstream's `src/` tree, which has its own MIT grant. See `NOTICE.md` for the per-file inventory and `src/LICENSE` for the grant text.

## Grant

Copyright (c) 2026 the cJSON Zig package contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Covered files

- `build.zig`, `build.zig.zon`, `zig/root.zig`, `zig/translate.h`, `tests.zig`, `smoke.zig`.
- `runtime/graph.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h`. The latter four are copied from this workspace's shared runtime core; see `FORK-NOTES.md`.
- `consumer/`.
- `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`.
- `cross-test.profile.sh`, `.gitignore`, `tools/check-provenance.sh`.
- `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md`.
- `testdata/malformed/*`, `testdata/values/*` (fixtures authored here).
- `README.upstream.md` is a byte-identical copy of upstream `src/README.md`. This fork's copy is covered here; upstream's text is covered by its own grant and is unchanged.

## Notices

`FORK-LICENSE.md` must accompany package copies. The copyright and permission notice above must appear in copies or substantial portions of covered files. `zig build` installs it at `share/licenses/cjson/FORK-LICENSE.md` beside upstream's `LICENSE.cJSON`, so installed copies carry both grants.

For upstream material, its copyright and permission notices must appear in all copies. `src/LICENSE` and `src/cJSON.h` travel with `src/`.
