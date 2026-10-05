//! The typed cJSON facade.
//!
//! `src/cJSON.c`, reached through `pub const c`, the module produced by
//! `b.addTranslateC` over `zig/translate.h`. What this module adds is a surface
//! that names an ownership rule for every value it hands back, an error set cut
//! at what it actually checked, and the two entry points that let a caller
//! choose how strict a parse is. It computes no JSON of its own: every value,
//! every offset and every error position comes from the compiled upstream C.
//!
//! ## Ownership is a type here, not a convention
//!
//! `Document` owns a parsed tree and has a `deinit`. `Owned` is a value the
//! caller owns and has a `deinit`. `Borrowed` is a value that belongs to
//! somebody else's tree and has *no* `deinit` at all, so there is no spelling
//! of this module that frees a member of a document. The three transitions
//! upstream defines -- hand a value over (`cJSON_AddItemToObject` and friends),
//! take one back (`cJSON_DetachItemFromObjectCaseSensitive`), replace one
//! (`cJSON_ReplaceItemInObjectCaseSensitive`) -- are the three ways the
//! ownership of a node changes, and each is one function here.
//!
//! ## The allocator is not this module's
//!
//! cJSON allocates through hooks this facade never installs: `cJSON_InitHooks`
//! is not called anywhere in this package, so `global_hooks` stays
//! `internal_malloc`/`internal_free`/`internal_realloc`
//! (`src/cJSON.c:169-186`), which are libc's `malloc`/`free`/`realloc`. Every
//! tree, every duplicated value and every printed buffer is therefore libc
//! memory, and `freePrinted` below hands it back through `cJSON_free`, the
//! hook-matched release upstream documents (`src/cJSON.h:152`). Nothing here is
//! freed with a Zig allocator, nothing is allocated with one, and a Zig test
//! framework cannot supply a leak oracle for memory this third-party allocator
//! owns. That is stated here because it is a real limit on what the tests can
//! prove, not a detail.
//!
//! ## Error taxonomy
//!
//! cJSON's header declares no error enumeration. `cJSON_Parse` and its
//! siblings return NULL, and the only diagnostic upstream offers is a pointer
//! into the input (`cJSON_GetErrorPtr`, `src/cJSON.h:181-182`). So this module
//! does not invent a reason code: `ParseError` has exactly the two members its
//! own checks can justify, and the position of the failure is a separate
//! function, `parseErrorOffset`. A caller that needs to know *why* a parse
//! failed has three honest inputs -- the offset, whether it asked for a strict
//! parse, and the input itself -- and this API adds no fourth.
//!
//! ## Linked or runtime-loaded
//!
//! *Linked* is the default. libcjson is linked and `c` is the translated header
//! itself. With `-Druntime=true` the same public surface resolves through one
//! process-lifetime table that an explicit `load(source)` fills, and nothing is
//! linked into the module; `runtime_loaded` says which, at comptime.

const std = @import("std");

/// The translated header, or the generated runtime dispatch over it.
///
/// Both configurations export the same declarations: the dispatch re-exports
/// the translation's own constants and types rather than compiling a second,
/// nominally distinct copy of them.
pub const c = @import("c");

/// The loader core, which carries `LoadSource` and `LoadError` in a linked
/// build. A runtime-loaded build gets both from the dispatch, and `createModule`
/// in `runtime/graph.zig` makes sure there is exactly one instance of this
/// module in the graph, which is what keeps those two types one type.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the library is linked. True when the
/// build generated a dispatch that resolves the same symbols through the
/// platform loader, in which case `load` is the call that makes the library
/// usable. It is a comptime constant, so a consumer can write two different
/// code paths and have only the one it chose analysed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly by calling
/// this again: there is no automatic retry and no implicit second source.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports both
/// configurations can tell the two apart at comptime.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "cjson: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// The six value kinds cJSON distinguishes, plus the two that are not values a
/// document can hold.
///
/// The bits are upstream's (`src/cJSON.h:89-97`) and are reported here by asking
/// upstream which one it is -- `cJSON_IsInvalid`, `cJSON_IsNull`, and so on
/// (`src/cJSON.h:189-198`) -- rather than by reading `item->type` through this
/// module. That is a deliberate choice: `type` is also the name of a Zig
/// primitive, so a translation of `src/cJSON.h:112` has to rename the field, and
/// a facade that reached for it would be coupled to that renaming. The `Is*`
/// functions answer the same question from the same bit and cannot drift.
pub const Type = enum {
    /// `item` was NULL. `cJSON_IsInvalid` is the one predicate that is true for
    /// a NULL argument (`src/cJSON.c:2957-2965`).
    invalid,
    null,
    false,
    true,
    number,
    string,
    array,
    object,
    /// `cJSON_Raw`: a pre-serialized fragment copied into the document without
    /// being parsed. It can only be created, never parsed, which is why it has
    /// no parse path anywhere in this module.
    raw,

    /// What `typeOf` reports for a value whose type bit is none of the above.
    /// Upstream's predicates are all false for it and `cJSON_Compare` rejects
    /// it (`src/cJSON.c:3077-3078`), so this facade reports it as `invalid`
    /// rather than inventing a member for it.
    pub fn of(value: Borrowed) Type {
        if (c.cJSON_IsInvalid(value.node) != 0) return .invalid;
        if (c.cJSON_IsNull(value.node) != 0) return .null;
        if (c.cJSON_IsTrue(value.node) != 0) return .true;
        if (c.cJSON_IsFalse(value.node) != 0) return .false;
        if (c.cJSON_IsNumber(value.node) != 0) return .number;
        if (c.cJSON_IsString(value.node) != 0) return .string;
        if (c.cJSON_IsArray(value.node) != 0) return .array;
        if (c.cJSON_IsObject(value.node) != 0) return .object;
        if (c.cJSON_IsRaw(value.node) != 0) return .raw;
        return .invalid;
    }
};

/// Whether an object member name is compared byte for byte or folded.
///
/// `cJSON_GetObjectItem` folds (`src/cJSON.h:178`, reached through
/// `get_object_item(..., false)` at `src/cJSON.c:1968-1971`) and
/// `cJSON_GetObjectItemCaseSensitive` does not (`src/cJSON.h:179`). The fold is
/// `tolower` over `unsigned char` (`src/cJSON.c:145-153`), so in a locale other
/// than "C" the set of bytes it folds is the locale's, and this module does not
/// pretend otherwise.
pub const Sensitivity = enum {
    case_sensitive,
    case_insensitive,

    fn toBool(self: Sensitivity) c.cJSON_bool {
        return switch (self) {
            .case_sensitive => 1,
            .case_insensitive => 0,
        };
    }
};

/// Whether a printed document is indented.
pub const Format = enum {
    /// `cJSON_PrintUnformatted`: no whitespace between tokens.
    compact,
    /// `cJSON_Print`: three spaces per level of depth, and the layout
    /// `src/tests/inputs/*.expected` records.
    formatted,
};

/// How strict a parse is.
pub const ParseOptions = struct {
    /// Refuse input that has anything after the first complete value except
    /// whitespace.
    ///
    /// This is upstream's `require_null_terminated` (`src/cJSON.h:158`), and
    /// with it `cJSON_Parse` changes meaning: without the flag it accepts
    /// `{"a":1} trailing` and stops at the first value (`src/cJSON.c:1174-1181`),
    /// while with it the same input is a failure. The flag only exists on the
    /// NUL-terminated entry points, which is why `parseBytes` refuses it rather
    /// than quietly ignoring it.
    require_null_terminated: bool = false,
};

/// Everything a parse can refuse.
///
/// The taxonomy stops where the checks stop. `ParseFailed` is not "the input is
/// bad": it is what upstream's NULL return says, and upstream returns NULL both
/// for input it rejects (`src/cJSON.c:1167-1171`) and for an allocation that
/// failed (`src/cJSON.c:1161-1165`). The header offers no way to tell those two
/// apart, so neither does this set. `NullTerminatedInputRequired` is the one
/// refusal this module owns: it is this file's own comparison of the caller's
/// request against the entry point's contract.
pub const ParseError = error{
    /// `parseBytes` was asked to require a NUL terminator.
    ///
    /// The counted entry point `cJSON_ParseWithLength`
    /// (`src/cJSON.h:155`, `src/cJSON.c:1227-1230`) is upstream's only way to
    /// parse a buffer that is not NUL-terminated, and it forwards
    /// `require_null_terminated` as `0` (`src/cJSON.c:1229`), so the request
    /// cannot be honoured. This is refused rather than dropped, because a caller
    /// that asked for a strict parse and got a lax one would not know.
    NullTerminatedInputRequired,
    /// Upstream returned NULL. See the type's comment for what that covers.
    ParseFailed,
};


/// Everything a creation can refuse.
///
/// Upstream's `cJSON_Create*` family returns NULL only when the allocation
/// fails -- `cJSON_New_Item` is the only thing that can fail inside it
/// (`src/cJSON.c:241-251`, `src/cJSON.c:2446-2594`) -- and the header reports
/// nothing else. `Duplicate` is the same shape: one `cJSON_New_Item` at
/// `src/cJSON.c:2769-2790`.
pub const CreateError = error{
    /// Upstream returned NULL because it could not allocate.
    OutOfMemory,
};
/// Everything a print can refuse.
///
/// `cJSON_PrintBuffered` returns NULL both when its buffer could not be grown
/// (`src/cJSON.c:485-483`, through `print` at `:1234-1299`) and when a value
/// has a type `print_value` cannot render (`src/cJSON.c:1486-1487`), and the
/// header reports neither. `PrintPreallocated` answers 0 in the same two
/// situations.
pub const PrintError = error{
    /// Upstream returned NULL, or 0 from `cJSON_PrintPreallocated`.
    PrintFailed,
};

/// Everything a mutation can refuse.
///
/// The `Add*`/`Insert*`/`Replace*` family returns `cJSON_bool` and only ever
/// returns 0 when an allocation failed (`src/cJSON.c:2012-2044`,
/// `:2319-2351`, `:2402-2410`); upstream's own callers treat it as "the item is
/// now owned by the container". That is what this facade reports.
pub const MutationError = error{
    /// Upstream refused the insertion, and the value passed in was *not* taken.
    ///
    /// The ownership half matters: on this error the caller still owns the value
    /// and must still release it. Upstream only attaches a value on success
    /// (`src/cJSON.c:2012-2044`).
    InsertionFailed,
    /// Upstream refused the replacement, and neither value's ownership changed.
    ReplacementFailed,
};

/// A parsed tree this caller owns.
pub const Document = struct {
    root: Owned,

    /// Release the tree and everything in it.
    ///
    /// `cJSON_Delete` (`src/cJSON.h:171`) frees the node, its children and its
    /// siblings, which is why releasing a subtree released only through its
    /// parent would be a double free. After this the document is unusable and
    /// this file does not defend against using it.
    pub fn deinit(self: *Document) void {
        self.root.deinit();
        self.root = undefined;
    }

    /// The root value, borrowed from this document.
    pub fn rootValue(self: *const Document) Borrowed {
        return self.root.borrow();
    }
};

/// A value this caller owns.
pub const Owned = struct {
    node: *c.cJSON,

    /// Release this value and everything under it.
    pub fn deinit(self: Owned) void {
        c.cJSON_Delete(self.node);
    }

    /// This value seen as a borrowed one.
    pub fn borrow(self: Owned) Borrowed {
        return .{ .node = self.node };
    }
};

/// A value that belongs to somebody else's tree.
///
/// There is deliberately no `deinit`. A member of a document is released by the
/// document's own `deinit`, and a spelling here that freed one would be a
/// double free that this module makes impossible to write.
pub const Borrowed = struct {
    node: *c.cJSON,

    /// The upstream node, for a caller that needs it. No ownership changes.
    pub fn raw(self: Borrowed) *c.cJSON {
        return self.node;
    }

    /// Which kind of value this is.
    pub fn kind(self: Borrowed) Type {
        return Type.of(self);
    }

    /// How many children this value has.
    ///
    /// `cJSON_GetArraySize` (`src/cJSON.h:174`) counts `child`/`next` without
    /// looking at the type (`src/cJSON.c:1884-1905`), so this is the member
    /// count of an object and the element count of an array, and it is 0 for
    /// every scalar. That is upstream's behaviour and this function does not add
    /// a type check it would then have to invent an error for.
    ///
    /// The count is an `int` upstream and this is a `usize`: a tree with more
    /// than `INT_MAX` children would overflow the C counter, which is upstream's
    /// own FIXME (`src/cJSON.c:1902-1903`), and no such tree fits in the memory
    /// this package can address on any target it builds.
    pub fn count(self: Borrowed) usize {
        const size = c.cJSON_GetArraySize(self.node);
        return if (size < 0) 0 else @intCast(size);
    }

    /// The child at `index`, counting from zero.
    ///
    /// Works for an object as well as an array: `get_array_item`
    /// (`src/cJSON.c:1907-1924`) walks the same chain `count` counts and never
    /// inspects the type. Out of range is null, and so is a negative index
    /// (`src/cJSON.c:1926-1933`), which a `usize` cannot express.
    pub fn at(self: Borrowed, index: usize) ?Borrowed {
        const size = c.cJSON_GetArraySize(self.node);
        if (size < 0 or index > @as(usize, @intCast(size))) return null;
        const item = c.cJSON_GetArrayItem(self.node, @intCast(index)) orelse return null;
        return .{ .node = item };
    }

    /// This object's member called `name`.
    ///
    /// Returns the *first* match. Upstream walks the chain and stops at the
    /// first element whose name compares equal (`src/cJSON.c:1945-1965`), so for
    /// a document with a repeated member name the answer is the first
    /// occurrence, and the later ones are reachable through `at` but never
    /// through this function. That is also what RFC 8259 section 4 leaves open
    /// for names that should be unique.
    pub fn field(self: Borrowed, name: [:0]const u8, sensitivity: Sensitivity) ?Borrowed {
        const item = switch (sensitivity) {
            .case_sensitive => c.cJSON_GetObjectItemCaseSensitive(self.node, name.ptr),
            .case_insensitive => c.cJSON_GetObjectItem(self.node, name.ptr),
        } orelse return null;
        return .{ .node = item };
    }

    /// Whether this object has a member called `name`, folded.
    ///
    /// This is `cJSON_HasObjectItem` (`src/cJSON.h:180`), which is upstream's
    /// own case-insensitive predicate; the name is spelled out here because a
    /// caller holding a `.case_sensitive` sensitivity needs `field` and cannot
    /// get it from this one.
    pub fn hasField(self: Borrowed, name: [:0]const u8) bool {
        return c.cJSON_HasObjectItem(self.node, name.ptr) != 0;
    }

    /// This value's member name, or null when it has none.
    ///
    /// Null for every array element and for a root value: upstream sets `string`
    /// only when a value is added to an object (`src/cJSON.c:2067-2102`) and
    /// never clears it, and `get_object_item` treats a NULL name as "not a
    /// match" (`src/cJSON.c:1961-1963`).
    pub fn memberName(self: Borrowed) ?[]const u8 {
        const name = self.node.string orelse return null;
        return std.mem.span(name);
    }

    /// This string's bytes, or null when this is not a string.
    ///
    /// `cJSON_GetStringValue` returns NULL for anything else
    /// (`src/cJSON.c:99-107`), including a raw value, so `.raw` has no string
    /// accessor here even though its `valuestring` is populated.
    pub fn stringValue(self: Borrowed) ?[]const u8 {
        const text = c.cJSON_GetStringValue(self.node) orelse return null;
        return std.mem.span(text);
    }

    /// This number's value, or null when this is not a number.
    ///
    /// This is `valuedouble`, the field upstream keeps exactly
    /// (`src/cJSON.h:119`). `valueint` is deliberately not exposed: it is a
    /// saturating `int` copy of the same number (`src/cJSON.c:388-400`), so a
    /// document holding `1e300` and one holding `2147483647` agree on
    /// `valueint` and disagree everywhere else. A caller that wants an integer
    /// narrows `f64` itself and owns the range check that implies.
    pub fn numberValue(self: Borrowed) ?f64 {
        if (c.cJSON_IsNumber(self.node) == 0) return null;
        return c.cJSON_GetNumberValue(self.node);
    }

    /// This boolean's value, or null when this is not a boolean.
    pub fn boolValue(self: Borrowed) ?bool {
        if (c.cJSON_IsTrue(self.node) != 0) return true;
        if (c.cJSON_IsFalse(self.node) != 0) return false;
        return null;
    }

    /// Whether this value is `null`.
    pub fn isNull(self: Borrowed) bool {
        return c.cJSON_IsNull(self.node) != 0;
    }

    /// Whether this value and `other` are equal under upstream's comparison.
    ///
    /// `cJSON_Compare` (`src/cJSON.h:261`) is not structural equality, and two
    /// of its rules are worth stating because they decide real answers:
    ///
    ///   * Two numbers are equal when they differ by no more than
    ///     `DBL_EPSILON` times the larger magnitude (`compare_double`,
    ///     `src/cJSON.c:584-588`). `0.1 + 0.2` therefore compares equal to
    ///     `0.3`, which bit-for-bit equality would refuse.
    ///   * Two objects are equal when each of one's members matches a member of
    ///     the other *by name*, compared in both directions
    ///     (`src/cJSON.c:3139-3174`), so member order does not matter and a
    ///     subset does not compare equal.
    pub fn equal(self: Borrowed, other: Borrowed, sensitivity: Sensitivity) bool {
        return c.cJSON_Compare(self.node, other.node, sensitivity.toBool()) != 0;
    }

    /// Add `value` to this object under `name`, taking ownership of it.
    ///
    /// This is the ownership transition in its plainest form. `value` is taken
    /// by value and consumed: on success the object owns the node and the
    /// caller must not release it, and on `InsertionFailed` nothing was
    /// attached and the value is still the caller's to release. Zig cannot make
    /// the first half impossible to write -- an `Owned` is a two-word value that
    /// can always be copied -- so the rule is stated here and the *return* of
    /// the detached form in `detachField` is the transition a caller can hold
    /// rather than remember.
    ///
    /// `cJSON_AddItemToObjectCS` (`src/cJSON.h:233`) is deliberately not
    /// wrapped here. Its "constant string" mode makes upstream skip copying the
    /// name and mark the node `cJSON_StringIsConst`, and the header's own
    /// warning (`src/cJSON.h:230-232`) is that writing to `item->string`
    /// afterwards is undefined. A facade that exposed it would hand a caller a
    /// lifetime rule it cannot check.
    pub fn put(self: Borrowed, name: [:0]const u8, value: Owned) MutationError!void {
        if (c.cJSON_AddItemToObject(self.node, name.ptr, value.node) == 0) {
            return MutationError.InsertionFailed;
        }
    }

    /// Append `value` to this array, taking ownership of it.
    pub fn append(self: Borrowed, value: Owned) MutationError!void {
        if (c.cJSON_AddItemToArray(self.node, value.node) == 0) {
            return MutationError.InsertionFailed;
        }
    }

    /// Insert `value` into this array at `index`, taking ownership of it.
    ///
    /// Index 0 puts the value first and index equal to the element count
    /// appends it, which is upstream's own rule (`src/cJSON.h:248`,
    /// `src/cJSON.c:2319-2351`). An index past the end is refused there and
    /// refused here, and a value refused that way is still the caller's.
    ///
    /// The comparison below is this module's own: upstream's index is a signed
    /// `int` (`src/cJSON.h:248`) and it refuses only a *negative* one
    /// (`src/cJSON.c:2319-2323`), so a `usize` above `INT_MAX` cannot be
    /// handed to it. An index past the element count reaches upstream and gets
    /// upstream's answer; this bound only stops a conversion that could not
    /// mean anything.
    pub fn insertAt(self: Borrowed, index: usize, value: Owned) MutationError!void {
        if (index > std.math.maxInt(c_int)) return MutationError.InsertionFailed;
        if (c.cJSON_InsertItemInArray(self.node, @intCast(index), value.node) == 0) {
            return MutationError.InsertionFailed;
        }
    }

    /// Take a member out of this object, which hands ownership to the caller.
    ///
    /// `cJSON_DetachItemFromObjectCaseSensitive` (`src/cJSON.h:243`) removes
    /// the node from the chain and returns it without freeing it, so the
    /// caller now owns exactly what it just removed and the document is one
    /// member shorter. Null is upstream's "no such member" answer, which is
    /// not an error here.
    pub fn detachField(self: Borrowed, name: [:0]const u8, sensitivity: Sensitivity) ?Owned {
        const node = switch (sensitivity) {
            .case_sensitive => c.cJSON_DetachItemFromObjectCaseSensitive(self.node, name.ptr),
            .case_insensitive => c.cJSON_DetachItemFromObject(self.node, name.ptr),
        } orelse return null;
        return .{ .node = node };
    }

    /// Remove a member from this object and release it.
    ///
    /// `cJSON_DeleteItemFromObjectCaseSensitive` (`src/cJSON.h:245`) detaches
    /// and then deletes, so the value is gone rather than returned: a caller
    /// that wants it should use `detachField` instead. This function's
    /// signature says so -- it returns nothing, because after it there is
    /// nothing to hold.
    pub fn deleteField(self: Borrowed, name: [:0]const u8, sensitivity: Sensitivity) void {
        switch (sensitivity) {
            .case_sensitive => c.cJSON_DeleteItemFromObjectCaseSensitive(self.node, name.ptr),
            .case_insensitive => c.cJSON_DeleteItemFromObject(self.node, name.ptr),
        }
    }

    /// Replace a member of this object with a new value, taking ownership of
    /// it.
    ///
    /// On success the object owns `value` and the old member has been
    /// released, which is upstream's rule (`src/cJSON.h:252`,
    /// `src/cJSON.c:2402-2434`). On `ReplacementFailed` nothing changed and
    /// the caller still owns `value`.
    pub fn replaceField(
        self: Borrowed,
        name: [:0]const u8,
        value: Owned,
        sensitivity: Sensitivity,
    ) MutationError!void {
        const ok = switch (sensitivity) {
            .case_sensitive => c.cJSON_ReplaceItemInObjectCaseSensitive(self.node, name.ptr, value.node),
            .case_insensitive => c.cJSON_ReplaceItemInObject(self.node, name.ptr, value.node),
        };
        if (ok == 0) return MutationError.ReplacementFailed;
    }
};

/// Parse a NUL-terminated document.
///
/// `text` is borrowed for the call and never retained; the tree it produces
/// holds copies of every byte, allocated by libc through upstream's hooks. On
/// success the document owns one value and the caller releases it with
/// `Document.deinit`.
///
/// `ParseOptions.require_null_terminated` is upstream's own flag: with it,
/// `cJSON_ParseWithOpts` (`src/cJSON.c:1126-1139`) skips trailing whitespace
/// and then requires a NUL, so `{"a":1} garbage` fails; without it, the same
/// input succeeds and the parse stops at the end of the object.
pub fn parse(text: [:0]const u8, options: ParseOptions) ParseError!Document {
    // The out-parameter is passed for both outcomes, including the empty input
    // upstream rejects on its own: the error position is process-wide state
    // (`src/cJSON.c:88-97`), so a parse this file refused before calling upstream
    // would leave a caller asking `parseErrorOffset` about an older failure.
    // `cJSON_ParseWithOpts` takes `const char **` (`src/cJSON.h:157`), which
    // `zig translate-c` spells `[*:c][*:c]const u8`: a many-item pointer whose
    // element is itself a C-pointer. The local is the inner pointer, and `&end`
    // is the single-item pointer that coerces into it -- a `?[*:0]const u8`
    // will not, because a NUL-terminated pointer and a C-pointer have
    // different sentinels. `end` is never read: upstream writes it, this module
    // reports the position through `parseErrorOffset` instead.
    var end: [*c]const u8 = undefined;
    const node = c.cJSON_ParseWithOpts(text.ptr, &end, @intFromBool(options.require_null_terminated)) orelse
        return ParseError.ParseFailed;
    return .{ .root = .{ .node = node } };
}

/// Parse a counted buffer that need not be NUL-terminated.
///
/// This is upstream's `cJSON_ParseWithLength` (`src/cJSON.h:155`), which is the
/// only entry point for a buffer whose last byte is data rather than a
/// terminator: it hands upstream the length instead of asking `strlen`
/// (`src/cJSON.c:1142-1158`). Upstream's own wrapper makes the length one longer
/// than the string only for the strict variant (`src/cJSON.c:1135-1136`), and
/// that variant is not reachable here -- see `ParseError.NullTerminatedInputRequired`.
///
/// A zero length is passed through rather than short-circuited: upstream
/// rejects it itself (`src/cJSON.c:1151-1154`) and records position 0
/// (`src/cJSON.c:1195-1215`), so the error state this module reports on is the
/// state that call actually produced.
pub fn parseBytes(bytes: []const u8, options: ParseOptions) ParseError!Document {
    if (options.require_null_terminated) return ParseError.NullTerminatedInputRequired;
    const node = c.cJSON_ParseWithLength(bytes.ptr, bytes.len) orelse
        return ParseError.ParseFailed;
    return .{ .root = .{ .node = node } };
}

/// Where the last failed parse stopped, as an offset into the buffer that was
/// parsed, or null when there is no such position.
///
/// `cJSON_GetErrorPtr` is a single process-wide position, not a per-call result
/// (`src/cJSON.c:88-97`), so this is only meaningful immediately after a failed
/// parse of `bytes` and only for that buffer. Two cases are handled rather than
/// assumed:
///
///   * After a *successful* parse upstream has cleared the position and the
///     buffer pointer together (`src/cJSON.c:1147-1150`), so the answer is
///     null: there was no error.
///   * If some other parse ran in between, the pointer belongs to that other
///     buffer. The comparison below refuses to report an offset into a buffer
///     the pointer does not lie in, because a fabricated offset is worse than
///     no offset.
///
/// The position itself is upstream's: on failure it is the parse offset, or the
/// last byte of the buffer when the parse consumed all of it
/// (`src/cJSON.c:1201-1208`). For input that is only whitespace the offset is
/// `len - 1` rather than `len`, because `buffer_skip_whitespace` walks the
/// offset past the end and then backs it up by one (`src/cJSON.c:1102-1105`).
pub fn parseErrorOffset(bytes: []const u8) ?usize {
    const at = c.cJSON_GetErrorPtr() orelse return null;
    const base = @intFromPtr(bytes.ptr);
    const offset = @intFromPtr(at);
    if (offset < base) return null;
    const delta = offset - base;
    if (delta > bytes.len) return null;
    return delta;
}

/// cJSON's own version string, exactly as upstream formats it.
///
/// A pass-through, not a re-derivation: `cJSON_Version` builds the string from
/// the three macros in the header with `sprintf("%i.%i.%i", ...)`
/// (`src/cJSON.c:124-131`), and this module does not format a second copy out
/// of `CJSON_VERSION_MAJOR`/`_MINOR`/`_PATCH`. The returned slice borrows
/// storage the library owns and stays valid for the life of the process.
pub fn version() []const u8 {
    const text = c.cJSON_Version() orelse return "";
    return std.mem.span(text);
}

/// Render a value as JSON text.
///
/// The returned buffer is libc memory from upstream's print hooks and belongs to
/// the caller, who releases it with `freePrinted`. It is NUL-terminated, and
/// `freePrinted` needs the original slice, not a copy of it: upstream's
/// allocator is the C library's and knows nothing of Zig slices.
pub fn print(value: Borrowed, format: Format) PrintError![]u8 {
    // The prebuffer is upstream's own default (`src/cJSON.c:1236`), so the first
    // allocation is the same one upstream would make.
    const text = c.cJSON_PrintBuffered(value.node, 256, @intFromBool(format == .formatted)) orelse
        return PrintError.PrintFailed;
    return std.mem.span(text);
}

/// Release a buffer `print` returned.
///
/// Upstream documents three interchangeable releases for a printed buffer --
/// stdlib `free`, the configured `free_fn`, or `cJSON_free`
/// (`src/cJSON.h:152`) -- and `cJSON_free` is the one that stays correct if a
/// caller installs its own hooks later, because it asks the hooks rather than
/// assuming libc. This facade never installs hooks, so today all three are the
/// same function; the choice is made here so that it is still right if that
/// ever changes.
pub fn freePrinted(text: []u8) void {
    c.cJSON_free(@ptrCast(@alignCast(text.ptr)));
}

/// Render a value into a buffer the caller owns.
///
/// Returns false, with the buffer's contents unspecified, when the buffer is
/// too small: `cJSON_PrintPreallocated` answers 0 and has already written what
/// it could (`src/cJSON.c:1343-1361`). Upstream's own header warns that the
/// estimate is not exact and that five spare bytes are worth allocating
/// (`src/cJSON.h:168`); that is upstream's advice about *this* function and is
/// reproduced here rather than worked around.
///
/// The value is borrowed. Note that upstream declares this entry point with a
/// mutable `cJSON *` (`src/cJSON.h:169`) although it only reads the tree -- a
/// const-correctness wart in the header, not a licence to modify it. This
/// function accepts a `Borrowed` and mutates nothing.
pub fn printInto(value: Borrowed, buffer: []u8, format: Format) bool {
    const length: c_int = @intCast(buffer.len);
    return c.cJSON_PrintPreallocated(value.node, buffer.ptr, length, @intFromBool(format == .formatted)) != 0;
}

/// An empty object, owned by the caller.
pub fn createObject() CreateError!Owned {
    const node = c.cJSON_CreateObject() orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// An empty array, owned by the caller.
pub fn createArray() CreateError!Owned {
    const node = c.cJSON_CreateArray() orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// A string value, owned by the caller.
///
/// `cJSON_CreateString` copies the bytes (`src/cJSON.c:2516-2531`), so `text`
/// need not outlive the call. The value is also escaped on output by the same
/// rules every parsed string is (`src/cJSON.c:949-1068`), so a NUL inside a
/// Zig string is not representable here and is not silently dropped: the
/// parameter is NUL-terminated, which is what upstream's `strlen`-based copy
/// (`src/cJSON.c:2523-2527`) requires.
pub fn createString(text: [:0]const u8) CreateError!Owned {
    const node = c.cJSON_CreateString(text.ptr) orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// A number value, owned by the caller.
pub fn createNumber(number: f64) CreateError!Owned {
    const node = c.cJSON_CreateNumber(number) orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// A boolean value, owned by the caller.
pub fn createBool(value: bool) CreateError!Owned {
    const node = c.cJSON_CreateBool(@intFromBool(value)) orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// A null value, owned by the caller.
pub fn createNull() CreateError!Owned {
    const node = c.cJSON_CreateNull() orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// Copy a value into memory the caller owns.
///
/// `cJSON_Duplicate` (`src/cJSON.h:255`) returns a new tree; with `recursive`
/// true it copies everything under the value, and with it false it copies the
/// node alone (`src/cJSON.c:2769-2790`). The copy is independent of the
/// original in both cases -- no node is shared -- so releasing both is correct,
/// and a caller that wanted the original released can do that after duplicating
/// rather than before.
pub fn duplicate(value: Borrowed, recursive: bool) CreateError!Owned {
    const node = c.cJSON_Duplicate(value.node, @intFromBool(recursive)) orelse
        return CreateError.OutOfMemory;
    return .{ .node = node };
}