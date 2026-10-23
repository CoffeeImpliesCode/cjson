# `cjson` Zig facade

## Types and ownership

| Type | Owns | Release |
|---|---|---|
| `Document` | Parsed tree | `deinit()` |
| `Owned` | Created or detached value | `deinit()` |
| `Borrowed` | Nothing | No release method |

Parsing returns a `Document`; creation and duplication return `Owned`; reads return `Borrowed`. `put`, `append`, `insertAt` and `replaceField` take an `Owned` value by value and transfer ownership on success. On failure, the caller still owns it. `detachField` transfers ownership back; `deleteField` removes and releases a member.

The facade does not install cJSON allocator hooks or use a Zig allocator. Release printed buffers with `freePrinted`.

## Parsing

```zig
parse(text: [:0]const u8, options: ParseOptions) ParseError!Document
parseBytes(bytes: []const u8, options: ParseOptions) ParseError!Document
parseErrorOffset(bytes: []const u8) ?usize
```

`ParseOptions.require_null_terminated` defaults to false. `parse` takes NUL-terminated input; without the option it stops after the first value, and with it true rejects trailing non-whitespace. `parseBytes` takes a counted buffer and refuses that option with `NullTerminatedInputRequired`.

`parseErrorOffset` reports the last failed parse's offset only for its input buffer and immediately after that parse. The error position is process-wide. `ParseError` is `NullTerminatedInputRequired` or `ParseFailed`; the latter covers upstream parse and allocation failures.

## Reading values

`Document.rootValue()` returns a `Borrowed`. Its methods are:

| Method | Result |
|---|---|
| `kind()` | `Type`: `invalid`, `null`, `false`, `true`, `number`, `string`, `array`, `object` or `raw` |
| `count()` | `usize` child count; works for objects and arrays |
| `at(index)` | `?Borrowed`; works for objects and arrays |
| `field(name, sensitivity)` | First matching `?Borrowed` member |
| `hasField(name)` | Case-insensitive `bool` membership check |
| `memberName()` | `?[]const u8`; null for a root or array element |
| `stringValue()` | `?[]const u8` |
| `numberValue()` | `?f64` |
| `boolValue()` | `?bool` |
| `isNull()` | `bool` |
| `equal(other, sensitivity)` | `bool`, using upstream comparison |
| `raw()` | Underlying `*c.cJSON` node |

`Sensitivity` is `.case_sensitive` or `.case_insensitive`. Missing members and out-of-range indexes return null. `equal` uses cJSON's numeric tolerance; object member order does not affect equality.

## Creating and mutating values

`createNull()`, `createBool(value)`, `createNumber(number)`, `createString(text)`, `createArray()` and `createObject()` return `CreateError!Owned`. `createString` copies a NUL-terminated string. `duplicate(value, recursive)` returns an independent copy; `recursive = false` copies only the node.

Methods on `Borrowed`:

- `put(name, value)` adds an object member.
- `append(value)` and `insertAt(index, value)` add an array item. The insertion index may equal the current count to append.
- `replaceField(name, value, sensitivity)` replaces a member.
- `detachField(name, sensitivity)` removes and returns an optional `Owned` value.
- `deleteField(name, sensitivity)` removes and releases a member.

`MutationError` is `InsertionFailed` or `ReplacementFailed`. Failed insertions and replacements leave the supplied value with the caller; a failed replacement does not change the existing member. `CreateError` is `OutOfMemory`.

## Printing

```zig
print(value: Borrowed, format: Format) PrintError![]u8
freePrinted(text: []u8) void
printInto(value: Borrowed, buffer: []u8, format: Format) bool
```

`Format` is `.compact` or `.formatted`. `print` returns a buffer to release with `freePrinted`. `printInto` returns false when the buffer is too small; its contents are then unspecified. Upstream recommends allowing five spare bytes. `PrintError` is `PrintFailed`.

## C interface and version

`c` exposes the translated `cJSON.h` declarations, constants and types. `version()` returns cJSON's version string, owned by the library and valid for the process lifetime.

## Runtime loading

`runtime_loaded` is a comptime boolean. `load(source: LoadSource) LoadError!void` loads an explicit provider before use. `LoadSource` is `.path` or `.system`; the loader does not fall back to another provider. A failed load can be retried explicitly; a successful load cannot be replaced by a different provider. Calls before loading panic. A provider must pass the loader's version, allocation, member-access and parse-error checks.

In a linked build, `runtime_loaded` is false, `loadedSource()` is null, and calling `load` panics.
