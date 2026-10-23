//! Typed Zig facade for cJSON. Trees use libc allocation; release owning values with `deinit`.
//! Parsing, printing, and mutation call upstream cJSON.

const std = @import("std");

/// Translated cJSON API, or runtime dispatch to it.
pub const c = @import("c");

const rt = @import("rt");

/// True when this build resolves native symbols at runtime; otherwise the library is linked.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Provider path or explicit system-library name for `load`.
/// A failed source is an error; there is no fallback.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned by `load`.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the runtime provider; a linked build panics.
/// Repeating the same request succeeds; a different request returns `ProviderMismatch`.
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

/// Return the successful load request, or null before load and in linked builds.
/// The returned path storage remains valid for the process lifetime.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// cJSON value kinds, plus `invalid` for NULL or unknown type bits.
pub const Type = enum {
    /// No value or an unknown cJSON type bit.
    invalid,
    null,
    false,
    true,
    number,
    string,
    array,
    object,
    /// A pre-serialized fragment; raw values cannot be parsed.
    raw,

    /// Classify a value using cJSON's type predicates.
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

/// Select byte-exact or case-insensitive member-name matching.
/// Case-insensitive matching follows C `tolower` and the active locale.
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

/// Whether printing uses cJSON's formatted layout.
pub const Format = enum {
    /// No whitespace between tokens.
    compact,
    /// Three spaces per nesting level for object members.
    formatted,
};

/// Controls trailing-data handling.
pub const ParseOptions = struct {
    /// Reject non-whitespace after the first value.
    /// `parseBytes` returns `NullTerminatedInputRequired` when this is true.
    require_null_terminated: bool = false,
};

/// Errors returned when parsing.
/// `ParseFailed` combines invalid input and allocation failure reported by upstream.
pub const ParseError = error{
    /// Returned when `parseBytes` receives `require_null_terminated = true`.
    NullTerminatedInputRequired,
    /// Upstream returned NULL while parsing.
    ParseFailed,
};

/// Errors returned by value creation and duplication.
pub const CreateError = error{
    /// Allocation failed.
    OutOfMemory,
};
/// Errors returned when printing.
pub const PrintError = error{
    /// Upstream returned NULL or reported failure.
    PrintFailed,
};

/// Errors returned by object and array mutation.
pub const MutationError = error{
    /// Insertion failed; the caller retains ownership of the value.
    InsertionFailed,
    /// Replacement failed; ownership is unchanged.
    ReplacementFailed,
};

/// A parsed tree owned by the caller.
pub const Document = struct {
    root: Owned,

    /// Release the tree and all descendants. Do not use the document afterward.
    pub fn deinit(self: *Document) void {
        self.root.deinit();
        self.root = undefined;
    }

    /// Return the root value as a borrow from this document.
    pub fn rootValue(self: *const Document) Borrowed {
        return self.root.borrow();
    }
};

/// A value owned by the caller.
pub const Owned = struct {
    node: *c.cJSON,

    /// Release this value and all descendants.
    pub fn deinit(self: Owned) void {
        c.cJSON_Delete(self.node);
    }

    /// Return this value as a non-owning borrow.
    pub fn borrow(self: Owned) Borrowed {
        return .{ .node = self.node };
    }
};

/// A non-owning value; keep its owner alive and release it through that owner.
pub const Borrowed = struct {
    node: *c.cJSON,

    /// Return the upstream node without changing ownership.
    pub fn raw(self: Borrowed) *c.cJSON {
        return self.node;
    }

    /// Return this value's kind.
    pub fn kind(self: Borrowed) Type {
        return Type.of(self);
    }

    /// Return child count: object members, array elements, or zero for scalars.
    /// Follows cJSON's untyped `GetArraySize` behavior.
    pub fn count(self: Borrowed) usize {
        const size = c.cJSON_GetArraySize(self.node);
        return if (size < 0) 0 else @intCast(size);
    }

    /// Return the child at zero-based `index`, or null when out of range.
    /// Works for objects and arrays.
    pub fn at(self: Borrowed, index: usize) ?Borrowed {
        const size = c.cJSON_GetArraySize(self.node);
        if (size < 0 or index > @as(usize, @intCast(size))) return null;
        const item = c.cJSON_GetArrayItem(self.node, @intCast(index)) orelse return null;
        return .{ .node = item };
    }

    /// Return the first member matching `name`, or null when absent.
    /// Duplicate names remain accessible by index.
    pub fn field(self: Borrowed, name: [:0]const u8, sensitivity: Sensitivity) ?Borrowed {
        const item = switch (sensitivity) {
            .case_sensitive => c.cJSON_GetObjectItemCaseSensitive(self.node, name.ptr),
            .case_insensitive => c.cJSON_GetObjectItem(self.node, name.ptr),
        } orelse return null;
        return .{ .node = item };
    }

    /// Return whether a case-insensitive member named `name` exists.
    pub fn hasField(self: Borrowed, name: [:0]const u8) bool {
        return c.cJSON_HasObjectItem(self.node, name.ptr) != 0;
    }

    /// Return the member name, or null for a root value or array element.
    pub fn memberName(self: Borrowed) ?[]const u8 {
        const name = self.node.string orelse return null;
        return std.mem.span(name);
    }

    /// Return string bytes, or null unless the value is a string.
    /// Raw values also return null.
    pub fn stringValue(self: Borrowed) ?[]const u8 {
        const text = c.cJSON_GetStringValue(self.node) orelse return null;
        return std.mem.span(text);
    }

    /// Return the number as `f64`, or null unless the value is numeric.
    pub fn numberValue(self: Borrowed) ?f64 {
        if (c.cJSON_IsNumber(self.node) == 0) return null;
        return c.cJSON_GetNumberValue(self.node);
    }

    /// Return the boolean value, or null unless this is a boolean.
    pub fn boolValue(self: Borrowed) ?bool {
        if (c.cJSON_IsTrue(self.node) != 0) return true;
        if (c.cJSON_IsFalse(self.node) != 0) return false;
        return null;
    }

    /// Return whether this value is `null`.
    pub fn isNull(self: Borrowed) bool {
        return c.cJSON_IsNull(self.node) != 0;
    }

    /// Compare values with cJSON's rules: approximate numbers and unordered object members.
    /// Member names are compared according to `sensitivity`.
    pub fn equal(self: Borrowed, other: Borrowed, sensitivity: Sensitivity) bool {
        return c.cJSON_Compare(self.node, other.node, sensitivity.toBool()) != 0;
    }

    /// Add a named member and transfer `value` on success.
    /// On `InsertionFailed`, the caller retains ownership of `value`.
    pub fn put(self: Borrowed, name: [:0]const u8, value: Owned) MutationError!void {
        if (c.cJSON_AddItemToObject(self.node, name.ptr, value.node) == 0) {
            return MutationError.InsertionFailed;
        }
    }

    /// Append `value`, transferring ownership on success.
    /// On `InsertionFailed`, the caller retains ownership.
    pub fn append(self: Borrowed, value: Owned) MutationError!void {
        if (c.cJSON_AddItemToArray(self.node, value.node) == 0) {
            return MutationError.InsertionFailed;
        }
    }

    /// Insert `value` at a zero-based index; `index == count` appends.
    /// Out-of-range or unrepresentable indexes return `InsertionFailed`; caller retains ownership.
    pub fn insertAt(self: Borrowed, index: usize, value: Owned) MutationError!void {
        if (index > std.math.maxInt(c_int)) return MutationError.InsertionFailed;
        if (c.cJSON_InsertItemInArray(self.node, @intCast(index), value.node) == 0) {
            return MutationError.InsertionFailed;
        }
    }

    /// Remove and return a matching member as an owned value; null means no match.
    pub fn detachField(self: Borrowed, name: [:0]const u8, sensitivity: Sensitivity) ?Owned {
        const node = switch (sensitivity) {
            .case_sensitive => c.cJSON_DetachItemFromObjectCaseSensitive(self.node, name.ptr),
            .case_insensitive => c.cJSON_DetachItemFromObject(self.node, name.ptr),
        } orelse return null;
        return .{ .node = node };
    }

    /// Remove and free a matching member. Use `detachField` to retain it.
    pub fn deleteField(self: Borrowed, name: [:0]const u8, sensitivity: Sensitivity) void {
        switch (sensitivity) {
            .case_sensitive => c.cJSON_DeleteItemFromObjectCaseSensitive(self.node, name.ptr),
            .case_insensitive => c.cJSON_DeleteItemFromObject(self.node, name.ptr),
        }
    }

    /// Replace a matching member and take ownership of `value`.
    /// On `ReplacementFailed`, ownership is unchanged.
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

/// Parse a NUL-terminated string into an owned document; the input is not retained.
/// Returns `ParseFailed` on upstream failure; strict mode rejects trailing non-whitespace.
pub fn parse(text: [:0]const u8, options: ParseOptions) ParseError!Document {
    // Pass the output pointer so cJSON updates its process-wide parse error position.
    // Translate-C uses this C-pointer local for the `const char **` parameter.
    var end: [*c]const u8 = undefined;
    const node = c.cJSON_ParseWithOpts(text.ptr, &end, @intFromBool(options.require_null_terminated)) orelse
        return ParseError.ParseFailed;
    return .{ .root = .{ .node = node } };
}

/// Parse a counted buffer; the input is borrowed and not retained.
/// `require_null_terminated` returns `NullTerminatedInputRequired`; upstream failures return `ParseFailed`.
pub fn parseBytes(bytes: []const u8, options: ParseOptions) ParseError!Document {
    if (options.require_null_terminated) return ParseError.NullTerminatedInputRequired;
    const node = c.cJSON_ParseWithLength(bytes.ptr, bytes.len) orelse
        return ParseError.ParseFailed;
    return .{ .root = .{ .node = node } };
}

/// Return the last parse offset in `bytes`, or null if there is no matching error pointer.
/// cJSON stores the pointer process-wide; call this after a failed parse of the same bytes.
pub fn parseErrorOffset(bytes: []const u8) ?usize {
    const at = c.cJSON_GetErrorPtr() orelse return null;
    const base = @intFromPtr(bytes.ptr);
    const offset = @intFromPtr(at);
    if (offset < base) return null;
    const delta = offset - base;
    if (delta > bytes.len) return null;
    return delta;
}

/// Return cJSON's version string, borrowed from process-lifetime library storage.
pub fn version() []const u8 {
    const text = c.cJSON_Version() orelse return "";
    return std.mem.span(text);
}

/// Print a borrowed value into a libc-allocated buffer owned by the caller.
/// Release the returned buffer with `freePrinted`; upstream failure returns `PrintFailed`.
pub fn print(value: Borrowed, format: Format) PrintError![]u8 {
    const text = c.cJSON_PrintBuffered(value.node, 256, @intFromBool(format == .formatted)) orelse
        return PrintError.PrintFailed;
    return std.mem.span(text);
}

/// Release a buffer returned by `print` using cJSON's configured allocator.
pub fn freePrinted(text: []u8) void {
    c.cJSON_free(@ptrCast(@alignCast(text.ptr)));
}

/// Print a borrowed value into caller-owned storage.
/// Returns false on failure; buffer contents are unspecified.
pub fn printInto(value: Borrowed, buffer: []u8, format: Format) bool {
    const length: c_int = @intCast(buffer.len);
    return c.cJSON_PrintPreallocated(value.node, buffer.ptr, length, @intFromBool(format == .formatted)) != 0;
}

/// Create an empty object owned by the caller; allocation failure returns `OutOfMemory`.
pub fn createObject() CreateError!Owned {
    const node = c.cJSON_CreateObject() orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// Create an empty array owned by the caller; allocation failure returns `OutOfMemory`.
pub fn createArray() CreateError!Owned {
    const node = c.cJSON_CreateArray() orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// Create a string value, copying `text`; the caller owns the result.
/// Allocation failure returns `OutOfMemory`.
pub fn createString(text: [:0]const u8) CreateError!Owned {
    const node = c.cJSON_CreateString(text.ptr) orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// Create a number owned by the caller; allocation failure returns `OutOfMemory`.
pub fn createNumber(number: f64) CreateError!Owned {
    const node = c.cJSON_CreateNumber(number) orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// Create a boolean owned by the caller; allocation failure returns `OutOfMemory`.
pub fn createBool(value: bool) CreateError!Owned {
    const node = c.cJSON_CreateBool(@intFromBool(value)) orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// Create a null value owned by the caller; allocation failure returns `OutOfMemory`.
pub fn createNull() CreateError!Owned {
    const node = c.cJSON_CreateNull() orelse return CreateError.OutOfMemory;
    return .{ .node = node };
}

/// Copy a borrowed value into an independent tree owned by the caller.
/// `recursive` copies descendants; allocation failure returns `OutOfMemory`.
pub fn duplicate(value: Borrowed, recursive: bool) CreateError!Owned {
    const node = c.cJSON_Duplicate(value.node, @intFromBool(recursive)) orelse
        return CreateError.OutOfMemory;
    return .{ .node = node };
}
