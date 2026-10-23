//! End-to-end example for the cJSON facade.
//! Parses, reads, builds, prints, and releases documents.

const std = @import("std");
const cjson = @import("cjson");

/// Environment variable naming the provider in runtime-loading builds.
const provider_variable = "CJSON_PROVIDER";

fn nativeReady(init: std.process.Init) void {
    if (comptime !cjson.runtime_loaded) return;
    if (cjson.loadedSource() != null) return;

    const value = init.environ_map.get(provider_variable) orelse {
        std.debug.print(
            "smoke.zig: this is a runtime-loading build and {s} is not set.\n" ++
                "Point it at a shared object exporting the cJSON API, for example\n" ++
                "the one `zig build -Dlinkage=dynamic -Doptimize=Debug` installs.\n",
            .{provider_variable},
        );
        std.process.exit(2);
    };
    if (value.len == 0 or value.len > 4096) {
        std.debug.print("smoke.zig: {s} is empty or longer than 4096 bytes.\n", .{provider_variable});
        std.process.exit(2);
    }
    cjson.load(.{ .path = value }) catch |err| {
        std.debug.print("smoke.zig: loading {s} failed: {t}\n", .{ value, err });
        std.process.exit(2);
    };
}

pub fn main(init: std.process.Init) !u8 {
    nativeReady(init);

    // This document contains one string, one array, and one boolean.
    const source: [:0]const u8 = "{\"name\":\"cjson\",\"tags\":[\"parse\",\"print\"],\"ready\":true}";

    var doc = try cjson.parse(source, .{});
    defer doc.deinit();
    const root = doc.rootValue();

    std.debug.print("cjson {s}: parsed {d} members\n", .{ cjson.version(), root.count() });

    const name = root.field("name", .case_sensitive) orelse return error.MissingMember;
    if (!std.mem.eql(u8, name.stringValue() orelse return error.NotAString, "cjson")) {
        return error.WrongName;
    }

    const tags = root.field("tags", .case_sensitive) orelse return error.MissingMember;
    if (tags.count() != 2) return error.WrongTagCount;
    if (!std.mem.eql(u8, tags.at(0).?.stringValue() orelse return error.NotAString, "parse")) {
        return error.WrongFirstTag;
    }

    const ready = root.field("ready", .case_sensitive) orelse return error.MissingMember;
    if ((ready.boolValue() orelse return error.NotABool) != true) return error.WrongReady;

    // Build a document and check its compact output.
    const built = try cjson.createObject();
    defer built.deinit();
    try built.borrow().put("answer", try cjson.createNumber(42));
    try built.borrow().put("note", try cjson.createString("owned by the container"));
    try built.borrow().put("nested", try cjson.createArray());

    const compact = try cjson.print(root, .compact);
    defer cjson.freePrinted(compact);
    const built_compact = try cjson.print(built.borrow(), .compact);
    defer cjson.freePrinted(built_compact);

    if (!std.mem.eql(u8, built_compact, "{\"answer\":42,\"note\":\"owned by the container\",\"nested\":[]}")) {
        std.debug.print("smoke.zig: printed {s}\n", .{built_compact});
        return error.UnexpectedPrintedForm;
    }

    std.debug.print("round trip: {s}\n", .{compact});
    std.debug.print("built:      {s}\n", .{built_compact});

    // Malformed input demonstrates a parse error and its byte offset.
    const bad: [:0]const u8 = "{\"a\":}";
    if (cjson.parse(bad, .{})) |parsed| {
        // Make the parsed document mutable for `deinit`.
        var good = parsed;
        good.deinit();
        return error.BadDocumentParsed;
    } else |_| {}
    const offset = cjson.parseErrorOffset(bad) orelse return error.NoErrorOffset;
    std.debug.print("rejected {s} at offset {d}\n", .{ bad, offset });

    std.debug.print("cjson smoke: every answer checked\n", .{});
    return 0;
}
