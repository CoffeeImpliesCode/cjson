# FORK-LICENSE.md — this fork's own grant

**SPDX-License-Identifier: MIT**

This file covers the files **this fork authored**. It does not cover anything
under `src/`, which is upstream cJSON and carries its own MIT grant — see
`NOTICE.md` for the per-file inventory and `src/LICENSE` for upstream's text.

## The grant

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

## Why MIT, and who the grant is from

The workspace rule is that per-project licences for a fork's own additions are
authorized where they match the project's primary upstream terms, and cJSON's
primary terms are MIT — `src/LICENSE`, and the notice in every one of its own
source files (`src/cJSON.h:1-21`). MIT it is.

Two things this grant does **not** do, stated so nobody has to infer them:

* It does not extend to upstream's files. `src/` is cJSON's, under
  `Copyright (c) 2009-2017 Dave Gamble and cJSON contributors`. A downstream
  that ships this package ships both grants, and this one is the second of the
  two.
* It does not attribute anything here to upstream's authors. `build.zig`,
  `zig/root.zig`, `runtime/graph.zig`, the documentation and the fixtures were
  written for this package.

## What is covered

| Path | What it is |
|---|---|
| `build.zig`, `build.zig.zon` | The build graph and the package manifest |
| `zig/root.zig` | The typed facade |
| `zig/translate.h` | The aggregate translation header |
| `tests.zig`, `smoke.zig` | The behavioural tests and the example |
| `runtime/graph.zig`, `runtime/library.zig` | This package's runtime-route wiring and its load-time descriptor |
| `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h` | Copied from this workspace's shared runtime core; see `FORK-NOTES.md`, "The shared runtime core" |
| `consumer/` | The separate consumer package |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | Nix and devenv packaging |
| `cross-test.profile.sh`, `.gitignore`, `.github/workflows/verify.yml`, `tools/check-provenance.sh` | Gate and repository hygiene |
| `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `FORK-LICENSE.md` | This fork's records |
| `testdata/malformed/*`, `testdata/values/*` | The fixtures authored here |

`README.upstream.md` is a byte-identical copy of `src/README.md`. It is covered
here as a copy this fork made and by upstream's own grant as upstream's text;
nothing in it was changed.

## The notice obligation

`FORK-LICENSE.md` must travel with any copy of this package, and the notice
above must appear in every copy or substantial portion of these files.
`zig build` installs it at `share/licenses/cjson/FORK-LICENSE.md` beside
upstream's `LICENSE.cJSON`, so an installed binary form carries both.

Upstream's own obligation is separate and unchanged: cJSON's MIT text requires
that its copyright notice and permission notice appear in all copies of *its*
material, and `src/LICENSE` and `src/cJSON.h:1-21` travel with `src/`. A private
repository removes none of it.