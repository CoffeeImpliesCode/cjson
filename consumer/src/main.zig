// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.

//! Consumes the `cjson` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("cjson")` here. No path reaches into the library's
//! own tree, so if this builds and produces the answers below, the module
//! contract is real: the typed facade, the translated header it re-exports as
//! `c`, and the native library behind both arrived through one dependency line.
//!
//! The answers are facts about JSON that RFC 8259 states independently of any
//! implementation -- the shape of the two-value example in section 13, the
//! escape forms in section 7, and the rule in section 6 that forbids a leading
//! zero -- so they do not come from the library that produced them. Any
//! mismatch exits non-zero.
//!
//! The same source builds against a linked package and against a
//! runtime-loaded one. `cjson.runtime_loaded` is a comptime constant, so the
//! difference is one branch and no duplicated program: in the runtime-loaded
//! build the provider is named on the command line (`--provider <path>`) or in
//! `CJSON_PROVIDER`, loaded once, and the same answers follow.

const std = @import("std");
const cjson = @import("cjson");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The provider this run should load, from `--provider <path>` or from
/// `CJSON_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build
/// that was not told which file to load says so rather than loading something
/// else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("CJSON_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export CJSON_PROVIDER with a shared object exporting the " ++
            "declarations of zig/translate.h. Nothing is loaded by default and " ++
            "no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}

/// The raw translated namespace, reached through the facade.
///
/// This is what a dependent writes when it needs a call the typed surface does
/// not carry. Here it is used for the one thing the typed surface deliberately
/// does not expose: the `cJSON` struct's own `type` field (`src/cJSON.h:112`),
/// whose Zig spelling the translator had to change because `type` is a Zig
/// keyword, so this package never names it. Asking upstream through
/// `cJSON_IsObject` instead answers the same question from the compiled library
/// and from the translated header at once, and it is the form a dependent can
/// rely on without knowing anything about that renaming.
fn upstreamSaysObject(value: cjson.Borrowed) bool {
    return cjson.c.cJSON_IsObject(value.raw()) != 0;
}

fn upstreamSaysNumber(value: cjson.Borrowed) bool {
    return cjson.c.cJSON_IsNumber(value.raw()) != 0;
}

pub fn main(init: std.process.Init) !u8 {
    if (comptime cjson.runtime_loaded) {
        const provider = try providerRequest(init);
        cjson.load(.{ .path = provider }) catch |err| {
            std.debug.print("consumer: loading {s} failed: {t}\n", .{ provider, err });
            return err;
        };
        std.debug.print("consumer: provider {s} is loaded\n", .{provider});
    } else {
        std.debug.print("consumer: linked build, no provider needed\n", .{});
    }

    // RFC 8259 section 13's second example, in compact form.
    const source: [:0]const u8 =
        "{\"precision\":\"zip\",\"Latitude\":37.7668,\"Longitude\":-122.3959}";

    var doc = try cjson.parse(source, .{});
    defer doc.deinit();
    const root = doc.rootValue();

    if (root.kind() != .object) {
        std.debug.print("consumer: root is {t}, not an object\n", .{root.kind()});
        return error.WrongRootKind;
    }
    if (root.count() != 3) {
        std.debug.print("consumer: {d} members, expected 3\n", .{root.count()});
        return error.WrongMemberCount;
    }

    const latitude = root.field("Latitude", .case_sensitive) orelse
        return error.MissingMember;
    const latitude_value = latitude.numberValue() orelse return error.NotANumber;
    if (latitude_value != 37.7668) {
        std.debug.print("consumer: Latitude is {d}, expected 37.7668\n", .{latitude_value});
        return error.WrongLatitude;
    }
    const longitude = root.field("Longitude", .case_sensitive) orelse
        return error.MissingMember;
    const longitude_value = longitude.numberValue() orelse return error.NotANumber;
    if (longitude_value != -122.3959) {
        std.debug.print("consumer: Longitude is {d}, expected -122.3959\n", .{longitude_value});
        return error.WrongLongitude;
    }

    // The same two questions asked twice: once through the typed surface and
    // once through the translated header. They must agree, and they do not have
    // to -- the typed surface answers from the `cJSON_Is*` functions and the raw
    // route answers from the same functions reached by their own names, so a
    // facade that mapped a value kind to the wrong `Type` would be caught here.
    if (!upstreamSaysObject(root)) {
        std.debug.print("consumer: cJSON_IsObject disagrees with the facade\n", .{});
        return error.WrongRootKind;
    }
    if (!upstreamSaysNumber(latitude)) {
        std.debug.print("consumer: cJSON_IsNumber disagrees with the facade\n", .{});
        return error.WrongValueType;
    }
    // The translated constants are the header's own, not this package's: the
    // facade re-exports them rather than restating them, so comparing against
    // them here is comparing the header against itself in one place and the
    // library against the header in the other.
    if (cjson.c.cJSON_Object != @as(c_int, 1 << 6) or cjson.c.cJSON_Number != @as(c_int, 1 << 3)) {
        std.debug.print("consumer: the translated type bits are not the header's\n", .{});
        return error.WrongTypeBits;
    }

    // Printing and re-reading gives the same document back, and re-printing
    // gives the same bytes: a formatter that was not idempotent would show up
    // here as a difference between the two prints.
    const once = try cjson.print(root, .compact);
    defer cjson.freePrinted(once);
    var again = try cjson.parseBytes(once, .{});
    defer again.deinit();
    const twice = try cjson.print(again.rootValue(), .compact);
    defer cjson.freePrinted(twice);
    if (!std.mem.eql(u8, once, twice)) {
        std.debug.print("consumer: printed twice: {s} then {s}\n", .{ once, twice });
        return error.PrintIsNotIdempotent;
    }

    // Section 6 of RFC 8259 forbids a leading zero, so this parser is more
    // permissive than the specification. A consumer has to know that, and the
    // facade documents it; the check is here so the permissiveness is observed
    // rather than assumed.
    var leading = cjson.parse("{\"a\":01}", .{}) catch |err| switch (err) {
        cjson.ParseError.ParseFailed => {
            std.debug.print("consumer: this build refuses a leading zero\n", .{});
            return error.UnexpectedlyStrict;
        },
        else => |e| return e,
    };
    defer leading.deinit();
    const zero = leading.rootValue().field("a", .case_sensitive) orelse
        return error.MissingMember;
    const zero_value = zero.numberValue() orelse return error.NotANumber;
    if (zero_value != 1) {
        std.debug.print("consumer: leading-zero member is {d}, expected 1\n", .{zero_value});
        return error.WrongLeadingZeroValue;
    }

    std.debug.print("consumer: {s}\n", .{once});
    std.debug.print("consumer: {d} members, Latitude {d}, Longitude {d}, all as written\n", .{
        root.count(),
        latitude_value,
        longitude_value,
    });
    std.debug.print("consumer: every answer checked\n", .{});
    return 0;
}