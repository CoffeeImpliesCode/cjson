# FORK-NOTES.md — decisions, boundaries, open questions

What a worker learned while writing this package, and what the driver has to
decide or observe. `CHANGELOG.md` for the change list and `UPSTREAM.md` for the
pin.

**Every behavioural statement in this file is `SOURCE-CONFIRMED`** — read out of
`src/` at the pinned tag or out of this repository's own files — except where a
boundary says `OBSERVED` and names the run that observed it. **The native gates
have been run; see `CHANGELOG.md` section 2. The 53-platform cross-target matrix
has now been run once: 53 cells, 19 pass, 33 `build_only`, 1 runtime failure,
recorded as boundary 2.6.**

---

## 1. Decisions, and the alternative that was rejected

### 1.1 Compile `src/cJSON.c` alone

Upstream's library source list is one file (`src/CMakeLists.txt:101`,
`set(SOURCES cJSON.c)`). This package compiles exactly that.

**Rejected:** adding `src/cJSON_Utils.c` to the same archive. It is defensible —
the file only calls `cJSON_*` functions that are already there, and one link
line would then deliver more upstream code — but upstream never puts
`cJSONUtils_*` inside `libcjson`, and a consumer reading a symbol table would see
a surface upstream does not ship. **Reversible** if the next wave wants the
utilities: it is one line in `library_sources` and one install rule.

### 1.2 Keep `-DENABLE_LOCALES` on

Upstream's default is ON (`src/CMakeLists.txt:273-276`). Turning it off would make
the build cheaper and locale-independent at the cost of diverging from the
configuration upstream tests.

**What the flag actually costs:** `localeconv()` is called on every number parsed
and every number printed (`src/cJSON.c:279-287`). The bytes on the wire are
unaffected in either direction, because parsing substitutes the locale separator
before `strtod` (`:366-376`) and printing replaces it back (`:641-652`). So this
is a performance and portability question, not a correctness one — and a locale
with a multi-byte separator is not representable in the single character
`get_decimal_point` returns, which is a latent upstream issue this package
inherits rather than introduces.

### 1.3 No version script, no generated `.def`

`-fvisibility=hidden` plus `CJSON_API_VISIBILITY` and `CJSON_EXPORT_SYMBOLS` — the
combination upstream's own default configuration uses (`src/CMakeLists.txt:86-90`)
— already makes `CJSON_PUBLIC` the whole export surface. fast_float needs a
linker arm for the opposite reason (its bridge header declares nothing), and
adding one here would be a second list to keep in step with a header that
already carries the answer.

**Consequence a reader should know:** a macOS shared object has a wider export
table than the ELF one, because `ld64` exports every global by default and this
build has no first-class way to narrow it. The C ABI a consumer calls is
identical.

### 1.4 Ownership as a type

`Document` and `Owned` have `deinit`; `Borrowed` has none. This is the cheapest
way to make "do not free a member of somebody else's tree" a compile error rather
than a comment, and it is what makes the ownership tests in `tests.zig`
meaningful: there is no `Borrowed.deinit` for a test to call by mistake.

**Not enforced, and stated:** `put`, `append`, `insertAt` and `replaceField` take
their value **by value**, so a caller can still copy an `Owned` first and release
it after handing it over. Zig cannot close that; the rule is on each function and
`detachField`'s return is the transition a caller can hold.

### 1.5 Two parse entry points, and one refusal

`parse` and `parseBytes` exist because upstream's do (`src/cJSON.h:154-159`), and
they are not the same function. `parseBytes` refuses
`require_null_terminated` rather than ignoring it, because
`cJSON_ParseWithLength` forwards the flag as `0` (`src/cJSON.c:1229`). Silently
dropping a caller's strictness request is the kind of quiet downgrade this
workspace's rules exist to prevent.

### 1.6 The fixture set is shared with the `simdjson` package

`testdata/rfc8259/*`, `testdata/large/twitter.json` and the fork-authored
documents are **byte-identical** in both packages, with the same recorded
digests. `tools/check-provenance.sh` checks the shared files against the digests
the sibling records, so a change on one side has to be made on the other in the
same commit.

**Why:** two independent JSON implementations measured on the same bytes is worth
more than either measured on its own. Both packages assert literal expected
values; neither compares its output to the other's, so a shared fixture cannot
make one implementation vouch for the other.

**The two documents that had to move:** `leading-zero.json` and
`unescaped-control-character.json` were originally filed as `malformed/` and are
now `values/`, because RFC 8259 forbids them and cJSON accepts them. Filing them
as must-reject documents would have been a test asserting a fact about the
specification rather than about this parser.

## 2. Boundaries

### 2.1 WASI cannot take a shared object

`std.Target.DynamicLinker.kind` is `.none` for WASI, so `-Dlinkage=dynamic` is
**refused** for that target with a message naming it — not downgraded to an
archive. `zig build check` with no flag still compiles the WASI cell, because the
default is `static`. Both the selected target and each matrix cell go through the
same `sharedObjectRefusal`, so the two paths cannot disagree.

### 2.2 System-library mode is withheld

There is no `b.systemIntegrationOption`. The full reasoning is in `UPSTREAM.md`,
"System-library mode". The short form: no installed cJSON was available here to
compare against, and `CJSON_NESTING_LIMIT` is a compile-time macro
(`src/cJSON.h:134-144`) that two builds of the same version can set differently,
so a header from one of them would misstate the other's behaviour. This is
recorded as *withheld*, which is not the same as satisfied.

### 2.3 Memory is libc's, and a leak oracle is impossible here

`cJSON_InitHooks` is never called in this package, so every tree and every
printed buffer is libc memory released through `cJSON_Delete` and `cJSON_free`.
A Zig test framework cannot observe those allocations. The tests here prove that
documented values come back; **they cannot prove the library does not leak**, and
no test in this package claims to. If that proof is ever needed it has to come
from a sanitizer run over a C program, not from this facade.

### 2.4 The number formatter depends on the C library

`print_number` uses `sprintf` with `%1.15g` and `%1.17g`
(`src/cJSON.c:618`, `:624`). Upstream's own recorded expectations
(`src/tests/print_number.c:84-101`) show no space before a positive number, which
means the reference runs' C library did not prefix one for the space flag in that
conversion. This package's tests assert upstream's table **byte for byte**.

**This is the single most likely place for a cross-platform failure**, and it is
named here rather than discovered later:

* *Condition*: a target's C library honours the space flag for `%g`, or prints a
  three-digit exponent as upstream's own helper works around for MinGW and older
  MSVC (`src/tests/print_number.c:46-61`).
* *Symptom*: `tests.zig`, "printed numbers are the strings upstream's own test
  suite records", fails with one leading space or one extra exponent digit in the
  diff.
* *Fix*: that is a *platform difference to record*, not a formatter bug. Fix it
  by recording the difference in this file and in `NOTICE.md` with the target that
  showed it — **not** by relaxing the comparison, which would turn an
  interoperability check into a self-check.
* *Targets bound*: whichever cells show it. Nothing here suggests which.

### 2.5 The error offsets are derived, not measured

`tests.zig` asserts an exact offset for eight malformed documents, each derived
from the parse path with the line references given beside it. The derivation is in
the test's comment. **It has not been executed.** If an offset disagrees, the
first thing to check is the derivation — in particular the `parse_string` failure
path, which reports one *past* the offending character
(`src/cJSON.c:940-943`), and the clamp for a position that ran off the end
(`src/cJSON.c:1201-1208`).

### 2.6 `armeb-linux` corrupts a variadic `double` at the call boundary

`OBSERVED` on the full 53-platform `cross-test` matrix, run from the package root
on 2026-10-05, run id `20261005-191618-17929-17203`, Zig 0.16.0. One cell of 53
failed to run: `armeb-linux`, 23 of 24 tests passed and one failed, harness exit
code 1. The failing test is the one named in boundary 2.4, and it fails on the
first fractional row rather than on a formatting difference:

```text
error: 'tests.test.printed numbers are the strings upstream's own test suite
       records' failed:
       expected this output: 0.123
       instead found this:   -8.2561318001325464e-225
```

`0.123` as a big-endian IEEE-754 double is `0x3fbf7ced_916872b0`. The value the
formatter received is `0x916872b0_3fbf7ced`: **the two 32-bit halves are
exchanged**. That is not a wrong answer from `sprintf`, it is a wrong argument
reaching it, and it is not this package's code:

* A C program containing no cJSON at all — one `sprintf(buf, "%1.15g", 0.123)`
  and a `printf("%a", ...)` — reproduces the same corruption under the same
  pinned compiler, and prints correctly for `arm-linux`, `riscv32-linux`,
  `x86-linux` and the host.
* The generated code is byte-identical between `armeb-linux` and `arm-linux`
  for the variadic call and its callee, so this is not a code-generation
  difference between the two targets.
* Every non-variadic path is correct on `armeb-linux`: arithmetic
  (`1.0/3.0`), a `volatile` double, a `register` double, `memcpy` of a double,
  and `snprintf` all return the correct bits. Zig's own `std.debug.print`
  formatter also formats `0.123` correctly on `armeb-linux`.
* Only the variadic crossing corrupts. A double that reaches a variadic callee
  through the register save area is exchanged half for half; a double pushed
  onto the overflow area past the eight VFP slots arrives correct.
* `-mfloat-abi=soft` on `armeb-linux` prints `0.123` correctly.
  `softfp` and `hard` both corrupt, so the VFP varargs save area is where the
  halves are exchanged.

**Boundary, not a defect here.** The corruption is in the big-endian ARM VFP
variadic call boundary of the pinned toolchain and its QEMU user-mode emulator
(`qemu-armeb`, 10.0.13, the runner `cross-test` detected for this target). cJSON
calls `sprintf` and `sscanf` with `double` arguments
(`src/cJSON.c:618`, `:624`, `:626`), which is correct C; the value is already
wrong before the call. **The comparison in `tests.zig` stays byte for byte.** No
fork file is changed to accommodate this, and the cell is reported as a runtime
failure, never as `build_only` and never as a pass.

* *Condition*: a big-endian ARM target whose runner delivers a variadic `double`
  through the VFP register save area.
* *Targets bound, as observed*: `armeb-linux` only. `armeb-netbsd` compiled but
  has no runner, so it is `build_only` coverage and this failure was never
  exercised there. The other four big-endian cells in the matrix —
  `aarch64_be-linux`, `mips64-linux`, `powerpc64-linux`, `s390x-linux` — and
  `thumbeb-linux` all passed 24 of 24.
* *If it is ever wanted green*: a QEMU or toolchain fix is required. Nothing in
  this fork can produce a correct `armeb-linux` variadic `double`, and editing
  the test to accept the corrupt output would turn an interoperability check
  into a self-check, which boundary 2.4 already forbids.

## 3. The shared runtime core

`runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c` and
`runtime/sync.h` were **copied** from this workspace's shared runtime core rather
than written for this package. That is a deliberate decision, not an omission:

* The three copies in this workspace (`lua`, `s2geometry`, `fast_float`) are
  byte-identical apart from the SPDX line, verified by digest before the copy.
* Rewriting them would put four subtly different loaders in one workspace and
  every loader bug would have to be fixed four times.
* `runtime/graph.zig` and `runtime/library.zig` **are** written for this package,
  and they are the files another SDK replaces: the former owns the wiring, the
  synchronization prefix and the routed-symbol classification, the latter owns
  the synchronization binding, the ABI statement and the load-time checks.

What this package changed in the copies: the SPDX line to MIT (cJSON's own
terms), and the include guard in `sync.h` from `LUA_RUNTIME_SYNC_H` to
`CJSON_RUNTIME_SYNC_H`. The guard must differ, and the prefix that ties the
copies together is `cjson_rt` in `runtime/graph.zig`, which has to agree with the
symbol names in `runtime/library.zig` — a build where they disagree does not
link, and that is the whole error report.

## 4. Open questions for the driver

Each of these is something a worker could not answer from source, or something
only a gate can settle. None is guessed at in the code.

| # | Question | Where it bites |
|---|---|---|
| 1 | Does the space flag in `%1.15g` prefix a space on any target's C library? | boundary 2.4; `tests.zig`'s printed-number table |
| 2 | Do all six `check` cells compile, and which of them can execute under the harness? | `zig build check`, `cross-test` |
| 3 | Does the 53-platform matrix hit a target whose `translate-c` produces no output for `<cJSON.h>`? | `cross-test`; nothing here depends on a particular libc closure, because the header includes only `<stddef.h>` |
| 4 | Does `wasm32-wasi` link the C archive and the test binary? | `zig build check` |
| 5 | Does `x86_64-windows-gnu` need `-DCJSON_IMPORT_SYMBOLS` anywhere in this package's own test or example? | `zig build check`; the installed `Cflags` carry it for consumers only |
| 6 | Is a loaded provider refused for the right reason when it is the wrong library? | `runtime/library.zig`'s four checks; no gate in this package loads a *wrong* provider |
| 7 | Does `zig build test` observe the same answers in ReleaseSafe as in Debug? | `zig build test` in both modes |

## 5. Lessons, in the shape a later wave can apply

Each is condition / symptom / fix / targets bound.

**5.1 — A translated C struct field whose name is a Zig keyword must not be named
by a facade.**
Condition: a C header declares a member called `type`, `error`, `align` or any
other Zig keyword. Symptom: the translated field is renamed by `translate-c`, and
any facade that reaches for it is coupled to a renaming it cannot see.
Fix: ask upstream through its own predicate functions — `cJSON_IsObject`,
`isnan`, and so on — which is what this package does, and say so in the facade.
Targets bound: any Zig SDK over a C library whose headers declare such a member.

**5.2 — A C library's flags belong in the upstream build definition, and the
honest move is to copy it.**
Condition: a vendored C library has a documented export-visibility mechanism in
its own header. Symptom: a build adds a linker version script or a `.def` file
because it assumes the header declares nothing. Fix: read the header; if the
header carries the mechanism, use it as upstream's build uses it and add no
second list. Targets bound: C SDKs whose public header has a
`*_PUBLIC`/`*_API_VISIBILITY` macro.

**5.3 — A library with no error enumeration cannot be given one.**
Condition: a C library returns `NULL` on every failure and offers a position
pointer. Symptom: a facade invents `error.SyntaxError`, `error.OutOfMemory`,
`error.DepthExceeded` and thereby promises a diagnosis upstream never made.
Fix: cut the error set at what the wrapper itself compared, expose upstream's
position as a separate function, and document that the header has no reason
code. Targets bound: cJSON, and any C library with this shape.

**5.4 — A fixture shared between two implementations must assert literals, not
agreement.**
Condition: two JSON libraries are packaged in one workspace and a common corpus
is proposed. Symptom: the test compares library A's output with library B's, so a
shared bug passes. Fix: share the bytes and the digests; assert literal expected
values in each package; document where each expected value came from. Targets
bound: this workspace's `cjson` and `simdjson` packages, and any future pair.

**5.5 — `sprintf("%1.15g", x)` is a portability dependency, not a formatting
detail.**
Condition: a formatter uses a conversion with the space flag on a floating-point
type. Symptom: the printed form gains a leading space on one C library, or a
three-digit exponent on another, and a byte-exact interoperability test fails.
Fix: record the difference per target; never relax the comparison. Targets
bound: every target whose C library is not the one upstream's CI used — named by
upstream as MinGW and pre-2015 MSVC in its own test helper.

**5.6 — A file the notice points at may not exist in the release.**
Condition: vendored third-party test material whose headers say "see
`license.txt`". Symptom: the licence obligation names a file the release does
not ship. Fix: look for it (`src/tests/unity/docs/license.txt` is present in
1.7.19), record where it is, and have the provenance gate check it is still
there. Targets bound: any SDK vendoring Unity.

**5.7 — A fixture that the specification forbids and the library accepts must be
filed as a divergence, not as a rejection.**
Condition: a permissive parser and a strict specification. Symptom: a test
labelled "malformed" asserts acceptance, or asserts rejection that does not come.
Fix: file it under the library's own behaviour, name the specification clause and
the source line, and test both directions — accepted, and what it prints. Targets
bound: this workspace's two JSON packages, and any conformance-suite work.