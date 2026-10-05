// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! cJSON's side of the runtime loader: the names its synchronization binding
//! has, what it requires of a provider beyond resolving its symbols, and what
//! the external ABI boundary for this provider actually is.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them cJSON's,
//! and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every declaration `zig/translate.h` reaches: the whole of `src/cJSON.h`.
//! There is no config-gated entry point in this configuration, so
//! `provider_optional` and `provider_excluded` in `runtime/graph.zig` are both
//! empty and a provider that does not export the whole set is refused rather
//! than half used.
//!
//! ## The ABI boundary, stated honestly
//!
//! The supported external ABI family is **cJSON 1.7.19 built from this
//! repository's `src/cJSON.h`, with `ENABLE_LOCALES` on**. That is a narrower
//! claim than "a shared object that exports these names", and the difference is
//! real:
//!
//!   * The `cJSON` struct has a fixed layout -- three pointers, an `int`, a
//!     `double`, and two `char *` (`src/cJSON.h:103-123`) -- and a consumer
//!     compiled against a header that ordered or sized those differently would
//!     read the wrong field of the same node. `valuedouble` in particular is a
//!     `double`, so a provider built where `double` is not eight bytes cannot
//!     answer a number at all.
//!   * `cJSON_Version()` returns the version formatted from the header's own
//!     macros (`src/cJSON.c:124-131`), so it is a statement about the header the
//!     provider was built with, not a claim about a file name. It is the family
//!     check below, and it is the only one available.
//!   * `CJSON_NESTING_LIMIT` and `CJSON_CIRCULAR_LIMIT` are compile-time macros
//!     in the header (`src/cJSON.h:134-144`), so a provider built with different
//!     values rejects documents at different depths under the same symbol
//!     names. The check below stays inside the limits this build uses
//!     (1000 levels), which any provider built from these headers also accepts.
//!   * The allocator is the provider's. `cJSON_InitHooks` (`src/cJSON.h:150`)
//!     can replace it, and the default hooks are libc's
//!     `malloc`/`free`/`realloc` (`src/cJSON.c:169-186`). Nothing in this SDK can
//!     observe, bound or account for those allocations: a Zig allocator is not
//!     in the path, and a test framework cannot supply a leak oracle for memory a
//!     third-party allocator owns. The checks below therefore *exercise* the
//!     allocator -- they allocate, print and release through the provider -- but
//!     they cannot prove it does not leak.
//!   * `cJSON_Hooks` and every `cJSON_bool` cross the boundary as function
//!     pointer and `int` respectively. On Windows the calling convention is
//!     upstream's `CJSON_CDECL`/`CJSON_STDCALL` (`src/cJSON.h:55-56`), so a
//!     provider built with a different convention under the same names is a
//!     different ABI.
//!
//! Resolving the symbols and translating the header is the boundary. They are not
//! proof that a provider is compatible, and this file does not pretend to add
//! more than it checks. What is checked at load time, before anything is
//! published:
//!
//!   * `cJSON_Version()` answers with this header's own version string. That is
//!     the ABI *family* check: it separates 1.7.19 from every other release
//!     upstream has shipped, and it is the only version statement the library
//!     makes about itself.
//!   * An object is created, a member is added under a name, and the object is
//!     released -- all through this same table. That is the allocator and
//!     teardown check, and doing the release here rather than at process exit is
//!     what keeps the check from leaking if it fails.
//!   * The member is found again by its exact name and reports back the number
//!     that was stored, which is the struct-layout check: `cJSON_AddItemToObject`
//!     writes the name through `item->string` (`src/cJSON.c:2067-2102`) and
//!     `cJSON_GetObjectItemCaseSensitive` compares it there
//!     (`src/cJSON.c:1945-1963`), so a provider whose `string` field is at a
//!     different offset cannot pass. The number stored is one whose exact value
//!     a `double` must return unchanged, so a provider with a narrower numeric
//!     type cannot pass either.
//!   * A document that is not JSON is refused, and the reported error position
//!     lies inside the buffer that was parsed. `cJSON_GetErrorPtr` is a pointer
//!     into the caller's own bytes (`src/cJSON.c:94-97`, `:1201-1215`), so a
//!     provider whose error position is relative to something else -- a copy, an
//!     offset base, an unrelated buffer -- produces a pointer outside this one
//!     and is refused. That is the error-channel check, and it is the only part
//!     of cJSON's single-word diagnostic this loader can test.
const std = @import("std");

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.c` compiled with
/// `RT_SYNC_PREFIX=cjson_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn cjson_rt_lock() void;
    extern fn cjson_rt_unlock() void;
    extern fn cjson_rt_wait() void;
    extern fn cjson_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn cjson_rt_thread_self() u64;

    pub fn lock() void {
        cjson_rt_lock();
    }
    pub fn unlock() void {
        cjson_rt_unlock();
    }
    pub fn wait() void {
        cjson_rt_wait();
    }
    pub fn broadcast() void {
        cjson_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return cjson_rt_thread_self();
    }
};

/// The version string this header describes, and the one a provider must report.
///
/// It is written out rather than assembled from `CJSON_VERSION_MAJOR`,
/// `CJSON_VERSION_MINOR` and `CJSON_VERSION_PATCH` on purpose: the provider
/// formats its own answer from those three macros with
/// `sprintf("%i.%i.%i", ...)` (`src/cJSON.c:124-131`), and re-deriving the same
/// string here would make the check agree with itself by construction instead of
/// by comparison.
const expected_version = "1.7.19";

/// A number whose exact value must survive the round trip through the provider.
///
/// `0.1` is chosen because it has no exact binary representation, so a provider
/// that stored or returned it as something narrower than a `double` could not
/// return the identical bit pattern. The comparison below is on the bits, not on
/// a tolerance.
const probe_number: f64 = 0.1;

/// The member name the probe adds and then looks up.
///
/// Mixed case on purpose: `cJSON_GetObjectItemCaseSensitive` compares with
/// `strcmp` (`src/cJSON.c:1948`) while `cJSON_GetObjectItem` folds case
/// (`src/cJSON.c:1955`), so looking this name up case-sensitively and expecting
/// it to be found is a statement about which of the two entry points the
/// provider actually ran.
const probe_name = "cjsonProbe";

/// A document no conforming parser accepts, and the reason it is not accepted.
///
/// The first character is not a value start: `parse_value` matches `-`, a digit,
/// `"`, `[`, `{`, and the four literals `null`, `true`, `false`
/// (`src/cJSON.c:1363-1414`), and `x` is none of them, so the parse fails at
/// offset 0 and the reported position is the first byte of the buffer.
const malformed = "x";

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "cjson";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The library-specific checks, run after every symbol resolved and
        /// before anything is published.
        ///
        /// A non-null answer is `ValidationFailed` and the candidate is closed
        /// without being published. Every check here is one whose failure this
        /// code can observe; see the module comment for what is deliberately not
        /// checked and why.
        pub fn validate(dst: *const table) ?[]const u8 {
            // The version the provider reports, straight out of its own
            // formatting code. A null answer means the provider could not even
            // produce a string, which is already a different library.
            const reported = dst.cJSON_Version() orelse
                return "cJSON_Version returned null, so this provider cannot state " ++
                    "which cJSON it implements";
            const text = std.mem.span(reported);
            if (!std.mem.eql(u8, text, expected_version)) {
                // The numbers go to the diagnostic stream rather than into the
                // returned text: `validate` has no allocator and the loader
                // reports whatever string it is given.
                std.debug.print(
                    "cjson: provider reports cJSON {s}, this SDK's headers " ++
                        "describe {s}; they are different external ABIs\n",
                    .{ text, expected_version },
                );
                return "this provider implements a different cJSON release " ++
                    "than the one this SDK's headers describe";
            }

            // Create and release one object through this same table. That is the
            // allocator and teardown check.
            const object = dst.cJSON_CreateObject() orelse return
                "cJSON_CreateObject returned null, so this provider's allocator " ++
                "could not satisfy a fresh object";
            defer dst.cJSON_Delete(object);

            const number = dst.cJSON_CreateNumber(probe_number) orelse return
                "cJSON_CreateNumber returned null, so this provider could not " ++
                "allocate a number node";
            defer dst.cJSON_Delete(number);

            // The insertion is the ownership transition: on success the object
            // owns the node, which is why the release above is the object's and
            // not this file's.
            if (dst.cJSON_AddItemToObject(object, probe_name, number) == 0) {
                return "cJSON_AddItemToObject refused an insertion into an empty " ++
                    "object it had just created";
            }

            // The layout check: the member has to be findable by its exact name,
            // and it has to report back the same number bit for bit.
            const found = dst.cJSON_GetObjectItemCaseSensitive(object, probe_name) orelse return
                "a member added under its exact name was not found again by " ++
                "cJSON_GetObjectItemCaseSensitive, so this provider's member " ++
                "chain is not the one these headers describe";
            if (dst.cJSON_IsNumber(found) == 0) {
                return "the member that was added as a number is not a number in " ++
                    "this provider, so its type field is at a different offset";
            }
            const seen = dst.cJSON_GetNumberValue(found);
            if (@as(u64, @bitCast(seen)) != @as(u64, @bitCast(probe_number))) {
                return "a number stored and read back did not return the same " ++
                    "value, so this provider's numeric type is not the double " ++
                    "these headers describe";
            }

            // The error-channel check. A provider whose error position is not a
            // pointer into this buffer cannot be the one these headers describe:
            // `cJSON_GetErrorPtr` is defined as an offset into the parsed text
            // (`src/cJSON.c:94-97`).
            if (dst.cJSON_Parse(malformed) != null) {
                return "a document that is not JSON parsed successfully, so this " ++
                    "provider is not a cJSON that refuses it";
            }
            const error_ptr = dst.cJSON_GetErrorPtr() orelse return
                "a failed parse left no error position, so this provider cannot " ++
                "report where parsing stopped";
            const first = @intFromPtr(&malformed);
            const at = @intFromPtr(error_ptr);
            if (at < first or at > first + malformed.len) {
                return "the error position for a failed parse does not lie inside " ++
                    "the buffer that was parsed, so this provider's error " ++
                    "reporting is not the one these headers describe";
            }

            return null;
        }
    };
}