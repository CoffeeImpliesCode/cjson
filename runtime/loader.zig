// SPDX-License-Identifier: MIT
//
//! Reusable runtime loader for translated C APIs.
//! A configuration supplies the symbols and table; the loader owns provider state and platform loading.

const std = @import("std");
const builtin = @import("builtin");

/// Selects an absolute file path or a platform-searched system name; the variants never fall back.
pub const LoadSource = union(enum) {
    /// Absolute path; relative paths are `InvalidSource`.
    path: []const u8,
    /// Basename or SONAME; separators and NUL bytes are `InvalidSource`.
    system: []const u8,
};

/// Errors returned by `load`.
pub const LoadError = error{
    /// Empty `.path` or `.system` input.
    EmptySource,
    /// Request exceeds `max_source_len`; its retained copy is never truncated.
    SourceTooLong,
    /// Paths must be absolute; system names cannot contain separators; neither may contain NUL.
    InvalidSource,
    /// Target has no dynamic loader; no provider is opened.
    UnsupportedTarget,
    /// The platform loader refused the request or a dependency.
    OpenFailed,
    /// A required symbol is missing; the candidate is closed and not published.
    MissingSymbol,
    /// Provider-specific validation refused the candidate before publication.
    ValidationFailed,
    /// A different request conflicts with the successful or in-flight provider.
    ProviderMismatch,
    /// The attempt's owner called `load` again.
    /// Returns instead of waiting on itself.
    ReentrantLoad,
};

/// Maximum request length, in bytes.
pub const max_source_len = 32768;

/// Fixed-size request copy, retained for process-lifetime comparisons.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Copies a validated request while the loader lock is held.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Returns the retained request, valid for the record's lifetime.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Requests match only when their variants and bytes match; paths are not normalized.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.target.os.tag == .windows)
                switch (std.Io.Dir.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.Io.Dir.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.Io.Dir.path.isSep(byte)) return error.InvalidSource;
                if (builtin.target.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// Loader phase for the configured table.
pub const Phase = enum(u8) {
    /// No successful load; a later call can retry.
    not_loaded = 0,
    /// A thread is filling the table; readers cannot see it.
    loading = 1,
    /// The table is published and routed calls are usable.
    ready = 2,
};

/// Release-published readiness flag for the generated dispatch table.
/// Readers use acquire loads before accessing table fields.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@backingInt(Phase.not_loaded)),

    /// Returns whether the table has been published.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @backingInt(Phase.ready);
    }

    /// Returns the phase for loader decisions.
    pub fn state(self: *const Ready) Phase {
        return @fromBackingInt(@intCast(self.phase.load(.acquire)));
    }

    /// Publishes or withdraws the phase using release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@backingInt(value), .release);
    }
};

/// Kinds of required export; both are resolved before publication.
pub const SymbolKind = enum {
    /// Table holds the exact translated function-pointer type.
    function,
    /// Table holds the provider-owned object address, not a copy.
    data,
};

/// One required export and its table representation.
pub const Symbol = struct {
    /// Export name as declared by the C header.
    name: [:0]const u8,
    /// Function or provider-owned data address.
    kind: SymbolKind,
};

/// Panics in every optimization mode when a routed call precedes a successful load.
/// The message includes the library and symbol names.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// True when the target supports `dlopen` or `LoadLibraryExW`.
/// WASI, Emscripten, and freestanding targets are unsupported.
pub const supported_target: bool = switch (builtin.target.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Process-global loader for one configuration.
/// Config supplies `library_name`, `table`, `symbols`, `tablePtr`, `ready`, `assign`, `optional_symbols`, `assignOptional`, `assignMissing`, `sync`, and optional `validate`.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// Table type supplied by the configuration.
        pub const table_type = Config.table;

        /// Current attempt, retained until its waiters consume the result.
        attempt: ?Attempt = null,

        /// Retained request copy; locked before readiness and immutable after publication.
        request: SourceRecord = .{},

        /// Loads the requested provider; safe to call from any thread.
        /// Same-request waiters share an attempt; retries wait for its waiters to drain.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // Ready fast path avoids taking the loader lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Join the existing attempt and return its result.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the record until every waiter has taken its result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // Do not start a retry until the previous attempt's waiters drain.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Open outside the lock; other callers wait on the attempt.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake all attached waiters; each must take this attempt's result.
            Config.sync.broadcast();
            // Keep the attempt record until every waiter has taken its result.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake callers waiting to retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Returns the successful request, or null before a load succeeds.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        /// The request already in use, checked against a new one.
        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // This follows an acquire read of the published readiness flag.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Opens, resolves, and validates without holding the loader lock.
        /// Closes the candidate on failure; publication happens after return.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    // Print validation details before returning the generic error.
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // Keep the handle while the table contains pointers into it.
            retain = true;
        }
    };
}

/// One in-flight or undrained attempt.
const Attempt = struct {
    /// Thread running the attempt, for reentrancy detection.
    owner: u64,
    /// Written under lock before waiters observe the completed phase.
    result: LoadError!void = error.OpenFailed,
    /// Keeps the attempt alive until every waiter reads its result.
    waiters: usize = 0,
};

/// Windows path buffer bound: UTF-8 bytes fit within the UTF-16 unit limit.
const windows_path_units = 32768;

const platform = if (builtin.target.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // `RTLD_NOW` reports dependency failures here; `RTLD_LOCAL` avoids cross-SDK lookup.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated pointer.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search standard directories for bare names; do not add the current directory.
    /// Paths with separators are loaded as named.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
