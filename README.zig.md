# `cjson` — the Zig API

The typed facade over cJSON 1.7.19. Every declaration here reaches the compiled
upstream C through `c`, the module `zig translate-c` produces from
`zig/translate.h`. Nothing in this API computes JSON.

**Status:** `SOURCE-CONFIRMED` throughout. Every `file:line` reference was read
out of `src/` at the pinned tag; no statement here was produced by running this
package.

---

## Contents

- [Three types, and why ownership is one of them](#three-types-and-why-ownership-is-one-of-them)
- [The allocator is not the caller's](#the-allocator-is-not-the-callers)
- [Parsing](#parsing)
- [The error taxonomy, and what it is not](#the-error-taxonomy-and-what-it-is-not)
- [Printing](#printing)
- [Reading](#reading)
- [Building and mutating](#building-and-mutating)
- [Comparing](#comparing)
- [The translated namespace](#the-translated-namespace)
- [Runtime loading](#runtime-loading)
- [Documented divergences from RFC 8259](#documented-divergences-from-rfc-8259)
- [Behaviour this API deliberately does not wrap](#behaviour-this-api-deliberately-does-not-wrap)

---

## Three types, and why ownership is one of them

| Type | Owns | Releases with |
|---|---|---|
| `Document` | a parsed tree | `Document.deinit` |
| `Owned` | a value the caller made or detached | `Owned.deinit` |
| `Borrowed` | nothing | **it has no `deinit`** |

`Borrowed` is what every read returns: a member of a document, an element of an
array, the root of a document. There is no spelling of this API that frees a
member of somebody else's tree, because the type that would do it has no such
method.

The three ownership transitions upstream defines are three functions:

| Transition | Function | What upstream does |
|---|---|---|
| give a value away | `put`, `append`, `insertAt`, `replaceField` | `cJSON_AddItemToObject` (`src/cJSON.h:229`), `cJSON_AddItemToArray` (`:228`), `cJSON_InsertItemInArray` (`:248`), `cJSON_ReplaceItemInObject` (`:251`) take ownership on success. On failure the caller still owns it, and this API's error names say so. |
| take one back | `detachField` | `cJSON_DetachItemFromObject` (`:239-245`) removes the node from the chain and returns it without freeing it. |
| remove and release | `deleteField` | `cJSON_DeleteItemFromObject` (`:240-245`) detaches and then deletes. |

`put`, `append`, `insertAt` and `replaceField` take the value **by value** and
consume it. Zig cannot make the second half of that rule impossible to write — an
`Owned` is a single pointer that can always be copied — so the rule is stated on
each function and the transition a caller can *hold* is `detachField`'s return.

## The allocator is not the caller's

cJSON allocates through hooks. **This package never installs any**: there is no
`cJSON_InitHooks` call anywhere in it, so `global_hooks` stays
`internal_malloc`/`internal_free`/`internal_realloc` (`src/cJSON.c:169-186`),
which are libc's `malloc`/`free`/`realloc`.

Three consequences, all of them load-bearing:

* Every tree, every duplicate and every printed buffer is libc memory. Nothing in
  this API allocates through a Zig allocator and nothing frees through one.
* `freePrinted` releases a printed buffer through `cJSON_free`, not through a
  Zig allocator. Upstream documents three interchangeable releases for a printed
  buffer — stdlib `free`, the configured `free_fn`, or `cJSON_free`
  (`src/cJSON.h:152`) — and `cJSON_free` is the one that asks the hooks rather
  than assuming libc. All three are the same function today; the choice is made
  here so it is still right if a caller installs hooks.
* A Zig test framework cannot supply a leak oracle for memory a third-party
  allocator owns. The tests here prove that documented values come back; they do
  not prove the library does not leak, and they do not claim to.

## Parsing

Two entry points, because upstream has two and they are not interchangeable.

### `parse(text: [:0]const u8, options: ParseOptions) ParseError!Document`

For a NUL-terminated buffer. This is `cJSON_ParseWithOpts` (`src/cJSON.h:158`),
and it is the only entry point that can honour
`options.require_null_terminated`.

```zig
var doc = try cjson.parse("{\"a\":1}", .{});
defer doc.deinit();
```

```zig
// Refuses `{"a":1} garbage`; without the flag the same text succeeds.
var strict = cjson.parse(text, .{ .require_null_terminated = true });
```

### `parseBytes(bytes: []const u8, options: ParseOptions) ParseError!Document`

For a counted buffer whose last byte is data. This is `cJSON_ParseWithLength`
(`src/cJSON.h:155`), which hands upstream the length instead of asking `strlen`
(`src/cJSON.c:1142-1158`). A mapped file, a network read and every fixture in
this package use this one.

```zig
var doc = try cjson.parseBytes(bytes, .{});
defer doc.deinit();
```

`require_null_terminated` is **refused** here, as
`error.NullTerminatedInputRequired`: `cJSON_ParseWithLength` forwards the flag
as `0` (`src/cJSON.c:1229`), so the request cannot be honoured, and a caller who
asked for strictness must not silently receive laxness.

An empty buffer is *not* special-cased here. Upstream rejects a zero length
itself (`src/cJSON.c:1151-1154`) and records position 0, so the error state this
API reports on is the state that call actually produced.

### `parseErrorOffset(bytes: []const u8) ?usize`

Where the last failed parse stopped, as an offset into the buffer that was
parsed.

```zig
if (cjson.parseBytes(bytes, .{})) |good| {
    good.deinit();
} else |_| {
    const offset = cjson.parseErrorOffset(bytes).?;
}
```

Three facts a caller needs, all from upstream's source:

* **It is process-wide state, not a per-call result.** `cJSON_GetErrorPtr` is one
  global `error` struct (`src/cJSON.c:88-97`). The answer is meaningful only
  immediately after a failed parse of *that* buffer.
* **After a success it is null.** `cJSON_ParseWithLengthOpts` clears both halves
  of the record before it parses (`src/cJSON.c:1147-1150`), so there is no
  stale position.
* **It is clamped, and the clamp is observable.** On failure the position is the
  parse offset, or the last byte when the parse ran off the end
  (`src/cJSON.c:1201-1208`). For whitespace-only input it is `len - 1`, because
  `buffer_skip_whitespace` walks past the end and then steps back by one
  (`:1102-1105`).

If a different parse ran in between, the pointer belongs to that other buffer.
`parseErrorOffset` compares the pointer against the buffer it was given and
returns null rather than reporting an offset into memory the caller did not
parse.

## The error taxonomy, and what it is not

```zig
pub const ParseError = error{ NullTerminatedInputRequired, ParseFailed };
pub const PrintError = error{ PrintFailed };
pub const MutationError = error{ InsertionFailed, ReplacementFailed };
pub const CreateError = error{ OutOfMemory };
```

**cJSON's header declares no error enumeration.** There is no `cJSON_STATUS_*`,
no reason code, nothing. `cJSON_Parse` and its siblings return NULL, and the
only diagnostic upstream offers is a pointer into the input.

So `ParseFailed` is not "the input is bad". It is what a NULL return says, and
upstream returns NULL both for input it rejects (`src/cJSON.c:1167-1171`) and
for an allocation that failed (`:1161-1165`). Distinguishing them would mean
inventing a reason code upstream does not have.

The taxonomy stops where this file's own checks stop. Each name is a claim about
a comparison this package made:

| Name | Whose check |
|---|---|
| `NullTerminatedInputRequired` | this file's: the caller asked a counted buffer for strictness |
| `ParseFailed` | upstream's NULL |
| `PrintFailed` | upstream's NULL from `cJSON_PrintBuffered`, or 0 from `cJSON_PrintPreallocated`; the header reports neither situation separately (`src/cJSON.c:1234-1299`, `:1343-1361`) |
| `InsertionFailed` | upstream's `cJSON_bool` 0 from the `Add`/`Insert` family, which is only ever an allocation failure (`src/cJSON.c:2012-2044`) |
| `ReplacementFailed` | upstream's `cJSON_bool` 0 from `cJSON_ReplaceItemIn*` |
| `OutOfMemory` | upstream's NULL from `cJSON_New_Item` (`src/cJSON.c:241-251`) or `cJSON_Duplicate` |

If you need to know *why* a parse failed, this API gives you three honest
inputs — the offset, whether you asked for a strict parse, and the input — and
adds no fourth.

## Printing

```zig
const text = try cjson.print(doc.rootValue(), .compact);
defer cjson.freePrinted(text);
```

`Format.compact` is `cJSON_PrintUnformatted` and `Format.formatted` is
`cJSON_Print`; both are reached here through `cJSON_PrintBuffered`
(`src/cJSON.h:162-166`) so one function carries both. The returned buffer is
libc memory and belongs to the caller.

The two formatters differ in more than whitespace, and the differences are
upstream's:

* **Arrays.** `print_array` (`src/cJSON.c:1590-1649`) emits `[`, the elements
  separated by `,`, and `]`. Formatted output adds **one space** after each
  comma and nothing else — no newline, no indentation, at any depth. So
  `[1,2,null]` prints as `[1,2,null]` compact and `[1, 2, null]` formatted,
  even inside a formatted object.
* **Objects.** `print_object` (`src/cJSON.c:1770-1881`) is the indented one: a
  newline after `{`, one **tab** per level of depth before each name, a tab
  after the `:` (`:1830`), a comma between members, and a closing `}` preceded
  by `depth - 1` tabs (`:1868-1875`). The indentation is a tab, not spaces.
* **Numbers.** See [the printed-number table](#the-printed-number-table) below.
* **Strings.** `"` and `\` are escaped; `\b \f \n \r \t` get their short forms;
  every byte below 32 becomes `\u00xx` with **lowercase** hex
  (`src/cJSON.c:991-998`, `:1058`); bytes above 31 are copied **without UTF-8
  validation** (`:1024-1028`).

`printInto(value, buffer, format)` renders into a caller-owned buffer and
returns `false` when it is too small, with the buffer's contents unspecified
(`src/cJSON.c:1343-1361`). Upstream's own header warns that its size estimate is
not exact and that five spare bytes are worth having (`src/cJSON.h:168`); that
advice is reproduced rather than worked around. Note that upstream declares this
entry point with a mutable `cJSON *` (`src/cJSON.h:169`) although it only reads;
this API takes a `Borrowed` and mutates nothing.

## Reading

Everything below is a method on `Borrowed`.

```zig
const root = doc.rootValue();

root.kind()                      // cjson.Type
root.count()                     // children: members of an object, elements of an array
root.at(index)                   // ?Borrowed, works for objects too
root.field("name", sensitivity)  // ?Borrowed, the first match by name
root.hasField("name")            // bool, case-folded
root.memberName()                // ?[]const u8, null for array elements and a root
root.stringValue()               // ?[]const u8
root.numberValue()               // ?f64
root.boolValue()                 // ?bool
root.isNull()                    // bool
root.equal(other, sensitivity)   // bool
root.raw()                       // [*c]cJSON, the upstream node
```

Details that decide real answers:

* **`kind()` asks upstream.** It calls `cJSON_IsObject` and its siblings
  (`src/cJSON.h:189-198`) rather than reading the struct's `type` field, because
  `type` is also the name of a Zig primitive and a translation of
  `src/cJSON.h:112` has to rename it. A facade coupled to that renaming would
  break the next time the translator changed its mind.
* **`count()` and `at()` do not type-check the container.** `cJSON_GetArraySize`
  walks `child`/`next` without looking at the type (`src/cJSON.c:1884-1905`) and
  `get_array_item` does the same (`:1907-1924`). Counting and indexing an object
  therefore work, and a scalar simply has no children. That is upstream's
  behaviour; this API does not add a type check it would then have to invent an
  error for.
* **`field()` returns the first match.** `get_object_item` walks the chain and
  stops at the first equal name (`src/cJSON.c:1945-1965`), so for a document
  with a repeated member name this is the first occurrence. Later occurrences
  are reachable through `at()` and never through this function — which is the
  behaviour RFC 8259 §4 leaves open for names that *should* be unique.
* **`Sensitivity` is not cosmetic.** `cJSON_GetObjectItem` folds
  (`src/cJSON.h:178`) and `cJSON_GetObjectItemCaseSensitive` does not (`:179`).
  The fold is `tolower` over `unsigned char` (`src/cJSON.c:145-153`), so outside
  the "C" locale the set of bytes it folds is the locale's.
* **`numberValue()` is `valuedouble` only.** `valueint` is deliberately not
  exposed: it is a **saturating `int` copy** of the same number
  (`src/cJSON.c:388-400`), so a document holding `1e300` and one holding
  `2147483647` agree on `valueint` and disagree everywhere else. A caller wanting
  an integer narrows `f64` itself and owns the range check that implies.
* **`memberName()` is null for array elements**, because upstream sets `string`
  only when a value is added to an object (`src/cJSON.c:2067-2102`) and never
  clears it, and `get_object_item` treats a NULL name as no match (`:1961-1963`).
* **Out of range is null, and so is an absent member.** Neither is an error.

### The printed-number table

`print_number` (`src/cJSON.c:591-658`) is not a plain `printf`:

1. NaN or infinity prints as `null` (`:606-610`).
2. A number equal to its own saturating `valueint` prints as `%d` (`:611-614`) —
   so `-0` prints as `0`, because `-0.0 == 0.0`.
3. Otherwise `%1.15g`, re-read with `%lg`, and accepted if the two agree within
   `DBL_EPSILON` times the larger magnitude (`compare_double`, `:584-588`);
   failing that, `%1.17g` (`:617-625`).

Upstream's own test suite records the resulting strings
(`src/tests/print_number.c:65-101`), and this package's tests use that table
directly:

| Input | Printed |
|---|---|
| `0` | `0` |
| `-1`, `-32768`, `-2147483648` | `-1`, `-32768`, `-2147483648` |
| `1`, `32767`, `2147483647` | `1`, `32767`, `2147483647` |
| `0.123` | `0.123` |
| `1e-09` | `1e-09` |
| `1000000000000` | `1000000000000` |
| `1.23e+129` | `1.23e+129` |
| `1.23e-126` | `1.23e-126` |
| `3.1415926535897931` | `3.1415926535897931` |
| `-0.0123` | `-0.0123` |
| `-1e-09` | `-1e-09` |
| `-1e+21` | `-1e+21` |
| `-1.23e+129` | `-1.23e+129` |
| `-1.23e-126` | `-1.23e-126` |

`1.7976931348623157e308` prints as `1.79769313486232e+308`: the 15-digit form
does not round-trip, but `compare_double`'s tolerance accepts it, so
`print_number` never reaches the 17-digit form
(`src/cJSON.c:584-588`, `:618-625`). Upstream's table notes that some
Windows toolchains print a three-digit exponent (`1e-009`, `1e+017`) and works
around it in its own assertion helper (`src/tests/print_number.c:46-61`); a
target that does that here is a platform difference to record, not a formatter
bug.

## Building and mutating

```zig
const object = try cjson.createObject();
defer object.deinit();

try object.borrow().put("name", try cjson.createString("cjson"));
try object.borrow().put("size", try cjson.createNumber(42));
try object.borrow().put("ready", try cjson.createBool(true));
try object.borrow().put("tags", try cjson.createArray());

try object.borrow().replaceField("size", try cjson.createNumber(7), .case_sensitive);
const taken = object.borrow().detachField("name", .case_sensitive); // Owned
object.borrow().deleteField("ready", .case_sensitive);               // gone
if (taken) |value| value.deinit();                                  // caller's
```

Every `create*` and `duplicate` returns `CreateError!Owned`, so an allocation
failure is a value and not a panic. Upstream's `cJSON_Create*` family returns
NULL only from `cJSON_New_Item` (`src/cJSON.c:241-251`), which is one
allocation.

`insertAt(array, index, value)` puts a value at `index`, shifting the rest right;
index 0 is first and index equal to the element count appends
(`src/cJSON.h:248`). This API refuses an index above `INT_MAX` in its own
comparison, because upstream's index is a signed `int` and it refuses only a
negative one (`src/cJSON.c:2319-2323`); an index past the end reaches upstream
and gets upstream's answer.

`duplicate(value, recursive)` returns an independent tree — no node is shared
(`src/cJSON.c:2769-2790`) — and with `recursive` false it copies the node alone.

**Not wrapped:** `cJSON_AddItemToObjectCS` (`src/cJSON.h:233`). Its
"constant string" mode makes upstream skip copying the name and mark the node
`cJSON_StringIsConst`, and the header's own warning (`:230-232`) is that writing
to `item->string` afterwards is undefined. A facade that exposed it would hand a
caller a lifetime rule it cannot check.

## Comparing

```zig
if (left.equal(right, .case_sensitive)) { ... }
```

`cJSON_Compare` (`src/cJSON.h:261`) is not structural equality, and two of its
rules decide real answers:

* **Numbers use a tolerance.** `compare_double` accepts `a` and `b` when
  `|a - b| <= max(|a|, |b|) * DBL_EPSILON` (`src/cJSON.c:584-588`). `0.1 + 0.2`
  therefore compares **equal** to `0.3`, whose bit patterns differ
  (`0x3FD3333333333334` against `0x3FD3333333333333`).
* **Objects compare by name, not by position.** Each of one's members is looked
  up in the other, in both directions (`src/cJSON.c:3139-3174`), so member order
  does not matter and a subset does **not** compare equal.

## The translated namespace

The facade re-exports the translation whole:

```zig
const cjson = @import("cjson");
cjson.c.cJSON_IsObject(node);
cjson.c.cJSON_VERSION_MAJOR;
```

`c` is the translated `cJSON.h` in a linked build and the generated runtime
dispatch over it under `-Druntime`, and both export the same declarations: the
dispatch re-exports the translation's own constants and types rather than
compiling a second, nominally distinct copy. So `cJSON_VERSION_MAJOR` here and
`cJSON_VERSION_MAJOR` behind the table are one value with one spelling.

This is where a dependent writes anything the typed surface deliberately
withholds. The facade does not name `item->type`, because `type` is a Zig keyword
and a translation of `src/cJSON.h:112` has to rename it; asking upstream through
`cJSON_IsObject` is the form that does not depend on that renaming.

## Runtime loading

```zig
if (cjson.runtime_loaded) {
    cjson.load(.{ .path = "/path/to/libcjson.so.1.7.19" }) catch |err| switch (err) {
        error.MissingSymbol => |symbol| ...,
        else => return err,
    };
}
```

`runtime_loaded` is a `comptime` constant, so a consumer that supports both
configurations writes two branches and has only the one it chose analysed.

The contract, in full: one process-lifetime table per module; explicit provider
selection (`.path` or `.system`); **no fallback** — a request that cannot be
honoured is an error, not a different library; atomic publication of a
successful table; an explicit retry after a failed attempt (there is no automatic
retry and no implicit second source); and an ordinary pre-initialization panic
in every optimization mode if a native call happens before a successful load.
Calling `load` again with the same request succeeds and changes nothing; calling
it with a *different* request after a success is `ProviderMismatch` and the
library already in use stays in use.

In a linked build there is no provider and nothing to resolve, so `load` stops
the program with a message saying so instead of quietly succeeding, and
`loadedSource()` returns null.

Before a table is published, a provider must pass the checks in
[`runtime/library.zig`](runtime/library.zig):

1. `cJSON_Version()` reports `1.7.19` — the ABI *family* check, and the only
   version statement cJSON makes about itself (`src/cJSON.c:124-131`).
2. An object, and a number, can be created and released — the allocator and
   teardown check.
3. A member added under an exact name is found again by
   `cJSON_GetObjectItemCaseSensitive` and reports back the same `double` bit for
   bit — the struct-layout and numeric-width check.
4. A document that is not JSON is refused, and the reported error position lies
   inside the buffer that was parsed — the error-channel check.

The supported external ABI family is **cJSON 1.7.19 built from this tree's
`src/cJSON.h` with `ENABLE_LOCALES` on**. On Windows the calling convention is
upstream's `CJSON_CDECL`/`CJSON_STDCALL` (`src/cJSON.h:55-56`). The check above
cannot observe whether a provider leaks, and does not claim to.

## Documented divergences from RFC 8259

This parser is more permissive than the specification in three places that a
consumer can hit. Each is pinned by a test with its upstream line reference.

| Input | RFC 8259 | This parser | Why |
|---|---|---|---|
| `{"a":01}` | §6 forbids a leading zero | **accepted**, `a == 1.0` | `parse_value` admits `-` or a digit (`src/cJSON.c:1399`), `parse_number` scans the whole `0-9 + - e E .` run (`:325-354`), and `strtod` consumes both digits as one decimal number (`:378`). |
| `{"a":"x<0x01>y"}` | §7 requires control characters to be escaped | **accepted**, and re-printed as `{"a":"x\u0001y"}` | `parse_string` copies every non-backslash byte with no check on its value (`:867-873`); `print_string_ptr` escapes bytes below 32 as `\u00xx` with lowercase hex (`:991-998`, `:1058`). |
| `{"a":1} trailing` | one value per document | **accepted** by `parse` without `require_null_terminated`; refused with it | `cJSON_ParseWithOpts` only looks past the first value when the flag is set (`:1174-1181`). |

And two places where it is *stricter* than a caller may expect:

| Input | Behaviour | Why |
|---|---|---|
| nesting deeper than 1000 | refused | `CJSON_NESTING_LIMIT` is 1000 (`src/cJSON.h:136-138`), checked before each level (`:1497-1501`, `:1657-1661`) |
| an unpaired UTF-16 surrogate in `\uXXXX` | refused | `utf16_literal_to_utf8` rejects a first unit in `DC00`-`DFFF` and a first unit in `D800`-`DBFF` with no valid second half (`:718-750`) |

## Behaviour this API deliberately does not wrap

| Not wrapped | Why |
|---|---|
| `cJSON_AddItemToObjectCS` | an unverifiable lifetime rule for the caller (above) |
| `cJSON_CreateStringReference`, `cJSON_CreateObjectReference`, `cJSON_CreateArrayReference` | each makes the new node point at memory the caller owns, and `cJSON_Delete` then does not free it (`src/cJSON.h:212-218`). That is a real facility and a real footgun; a facade that exposed it would need a lifetime type this one does not have. |
| `cJSON_Minify` | it rewrites the caller's buffer in place (`src/cJSON.h:266`), which is the one operation in this library that cannot be done on a borrow. |
| `cJSON_PrintPreallocated` | wrapped, but as `printInto` returning `bool` rather than a `cJSON_bool`, because the C type is `int` and the meaning is "false", not "0". |
| `cJSON_SetIntValue`, `cJSON_SetNumberValue`, `cJSON_SetBoolValue` | macros, not functions (`src/cJSON.h:281-293`). The first two expand to field writes or to `cJSON_SetNumberHelper`, which is wrapped through `createNumber` and the `number` values themselves; the third writes `item->type` and would reintroduce the renamed field. |
| `cJSON_malloc`, `cJSON_free` | exposed only as `freePrinted`, because the only memory this API hands back is a printed buffer. |
| `cJSON_CreateIntArray`, `cJSON_CreateFloatArray`, `cJSON_CreateDoubleArray`, `cJSON_CreateStringArray` | conveniences over `createNumber`/`createString` and an append loop, whose header comment carries a bound the caller has to keep (`:220-225`). |

## How this is verified

`zig build test` runs [`tests.zig`](tests.zig), which reads the fixture corpus
through the build-created module `cjson_paths`. In a `-Druntime` build every test
reaches the library through the loader and needs `CJSON_PROVIDER` pointing at a
shared object; nothing is loaded by default.

`zig build check` compiles all six required targets without running anything.
Nothing in this document was produced by running either.