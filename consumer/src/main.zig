// SPDX-License-Identifier: MIT
// See ../FORK-LICENSE.md for what that identifier covers.

//! Consumes `cjson` through the package dependency's public module.
//! The same checks run against linked and runtime-loaded configurations.

const std = @import("std");
const cjson = @import("cjson");

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// Reads the provider path from `--provider` or `CJSON_PROVIDER`.
/// It does not search a default location.
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

/// Calls `cJSON_IsObject` through the translated C namespace.
/// This checks the raw ABI path beside the facade's typed API.
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

    // Compare object and number checks through the typed facade and translated header.
    if (!upstreamSaysObject(root)) {
        std.debug.print("consumer: cJSON_IsObject disagrees with the facade\n", .{});
        return error.WrongRootKind;
    }
    if (!upstreamSaysNumber(latitude)) {
        std.debug.print("consumer: cJSON_IsNumber disagrees with the facade\n", .{});
        return error.WrongValueType;
    }
    if (cjson.c.cJSON_Object != @as(c_int, 1 << 6) or cjson.c.cJSON_Number != @as(c_int, 1 << 3)) {
        std.debug.print("consumer: the translated type bits are not the header's\n", .{});
        return error.WrongTypeBits;
    }

    // Reprinting parsed output must produce identical bytes.
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

    // RFC 8259 forbids leading zeroes; this probe records cJSON's permissive behavior.
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
