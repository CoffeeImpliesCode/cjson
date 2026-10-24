// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! Runtime descriptor for cJSON 1.7.19 built from this repository's header with `ENABLE_LOCALES`.
//! It probes version, object/member and number round trips, allocation, and parse-error pointer bounds.
//! These probes do not prove full ABI compatibility or leak freedom; providers must match layout, limits, and calling convention.
const std = @import("std");

const rt = @import("rt");

/// Synchronization ABI shared with `runtime/sync.c`.
/// The core has no symbol names, so each configured loader keeps separate state.
pub const Sync = struct {
    extern fn cjson_rt_lock() void;
    extern fn cjson_rt_unlock() void;
    extern fn cjson_rt_wait() void;
    extern fn cjson_rt_broadcast() void;
    // Matches `unsigned long long` on the supported targets.
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

/// Version string reported by `cJSON_Version`, compared before publication.
/// Keep it literal so the check compares against the provider's own answer.
const expected_version = "1.7.19";

/// Non-exact binary fraction used to test the provider's number round trip.
/// Validation compares the returned bits, not a tolerance.
const probe_number: f64 = 0.1;

/// Mixed-case name distinguishes the case-sensitive lookup from the case-folding lookup.
const probe_name = "cjsonProbe";

/// Invalid JSON whose error pointer must lie inside the input buffer.
const malformed = "x";

/// Loader configuration for this SDK's generated dispatch.
/// `dispatch` supplies the table and symbol lists.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name used in the pre-load panic.
        pub const library_name = "cjson";

        /// Generated table and symbol lists from the translated header.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

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

        /// Runs provider ABI probes after symbol resolution and before publication.
        /// Returns a refusal message when a probe fails.
        pub fn validate(dst: *const table) ?[]const u8 {
            const reported = dst.cJSON_Version() orelse
                return "cJSON_Version returned null, so this provider cannot state " ++
                    "which cJSON it implements";
            const text = std.mem.span(reported);
            if (!std.mem.eql(u8, text, expected_version)) {
                // Log provider version details; the refusal result has no allocator.
                std.debug.print(
                    "cjson: provider reports cJSON {s}, this SDK's headers " ++
                        "describe {s}; they are different external ABIs\n",
                    .{ text, expected_version },
                );
                return "this provider implements a different cJSON release " ++
                    "than the one this SDK's headers describe";
            }

            // Exercise provider allocation and teardown through the resolved table.
            const object = dst.cJSON_CreateObject() orelse return "cJSON_CreateObject returned null, so this provider's allocator " ++
                "could not satisfy a fresh object";
            defer dst.cJSON_Delete(object);

            const number = dst.cJSON_CreateNumber(probe_number) orelse return "cJSON_CreateNumber returned null, so this provider could not " ++
                "allocate a number node";
            var owns_number = true;
            defer if (owns_number) dst.cJSON_Delete(number);

            // Successful insertion transfers node ownership to the object.
            // Release the object, not the inserted node.
            if (dst.cJSON_AddItemToObject(object, probe_name, number) == 0) {
                return "cJSON_AddItemToObject refused an insertion into an empty " ++
                    "object it had just created";
            }
            owns_number = false;

            // Verify exact-name lookup and number bits through the provider.
            const found = dst.cJSON_GetObjectItemCaseSensitive(object, probe_name) orelse return "a member added under its exact name was not found again by " ++
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

            // `cJSON_GetErrorPtr` must point inside this input buffer.
            if (dst.cJSON_Parse(malformed)) |unexpected| {
                dst.cJSON_Delete(unexpected);
                return "a document that is not JSON parsed successfully, so this " ++
                    "provider is not a cJSON that refuses it";
            }
            const error_ptr = dst.cJSON_GetErrorPtr() orelse return "a failed parse left no error position, so this provider cannot " ++
                "report where parsing stopped";
            const first = @intFromPtr(malformed);
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
