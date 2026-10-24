//! Behavioral tests for the cJSON facade.
//! Covers RFC examples, upstream output, malformed input, ownership, and fixtures.

const std = @import("std");
const cjson = @import("cjson");

/// Directory containing the fixture corpus.
const paths = @import("cjson_paths");

/// Environment variable naming the provider in runtime-loading builds.
const provider_variable = "CJSON_PROVIDER";

/// Read bound above the largest fixture size.
const fixture_limit: std.Io.Limit = .limited(1 << 20);

/// Load the runtime provider once before tests call the facade.
fn nativeReady() void {
    if (comptime !cjson.runtime_loaded) return;
    if (cjson.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = std.testing.environ.getAlloc(std.testing.allocator, provider_variable) catch
        missingProvider();
    defer std.testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    cjson.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting the cJSON API, " ++
            "for example the one `zig build -Dlinkage=dynamic -Doptimize=Debug` " ++
            "installs, and export it for the whole `zig build` run.",
    );
}

/// Read one counted fixture from the build-root-relative corpus.
fn readFixture(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, fixture_limit);
}

fn parseFixture(bytes: []const u8) !cjson.Document {
    return cjson.parseBytes(bytes, .{}) catch {
        std.debug.print("tests.zig: fixture did not parse: {s}\n", .{bytes[0..@min(bytes.len, 80)]});
        return error.FixtureDidNotParse;
    };
}

/// Return member `name` as `f64`, or `MissingMember`/`NotANumber`.
fn number(doc: cjson.Borrowed, name: [:0]const u8) !f64 {
    const member = doc.field(name, .case_sensitive) orelse return error.MissingMember;
    return member.numberValue() orelse return error.NotANumber;
}

/// Return member `name` as text, or `MissingMember`/`NotAString`.
fn string(doc: cjson.Borrowed, name: [:0]const u8) ![]const u8 {
    const member = doc.field(name, .case_sensitive) orelse return error.MissingMember;
    return member.stringValue() orelse return error.NotAString;
}

test "runtime provider validation completes before publication" {
    if (comptime !cjson.runtime_loaded) return error.SkipZigTest;
    nativeReady();
    try std.testing.expect(cjson.loadedSource() != null);
    try std.testing.expectEqualStrings("1.7.19", cjson.version());
}

test "RFC 8259 section 13: the example object keeps every member and value the RFC prints" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/rfc8259/13-object.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(cjson.Type.object, root.kind());
    try std.testing.expectEqual(@as(usize, 1), root.count());

    const image = root.field("Image", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(cjson.Type.object, image.kind());
    try std.testing.expectEqual(@as(usize, 6), image.count());
    try std.testing.expectEqualStrings("View from 15th Floor", try string(image, "Title"));
    try std.testing.expectEqual(@as(f64, 800), try number(image, "Width"));
    try std.testing.expectEqual(@as(f64, 600), try number(image, "Height"));
    try std.testing.expectEqual(false, (image.field("Animated", .case_sensitive) orelse
        return error.MissingMember).boolValue() orelse return error.NotABool);
    try std.testing.expectEqual(true, image.field("Animated", .case_sensitive).?.isNull() == false);

    try std.testing.expectEqualStrings("Animated", image.at(4).?.memberName() orelse
        return error.MissingName);

    const thumbnail = image.field("Thumbnail", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqualStrings(
        "http://www.example.com/image/481989943",
        try string(thumbnail, "Url"),
    );
    try std.testing.expectEqual(@as(f64, 125), try number(thumbnail, "Height"));
    try std.testing.expectEqual(@as(f64, 100), try number(thumbnail, "Width"));

    // The RFC prints these four integer IDs in this order.
    const ids = image.field("IDs", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(cjson.Type.array, ids.kind());
    try std.testing.expectEqual(@as(usize, 4), ids.count());
    const expected_ids = [_]f64{ 116, 943, 234, 38793 };
    for (expected_ids, 0..) |expected, index| {
        const element = ids.at(index) orelse return error.MissingElement;
        try std.testing.expectEqual(expected, element.numberValue() orelse return error.NotANumber);
    }
    try std.testing.expectEqual(@as(?cjson.Borrowed, null), ids.at(4));
}

test "RFC 8259 section 13: the two records in the example array keep their coordinates" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/rfc8259/13-array.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(cjson.Type.array, root.kind());
    try std.testing.expectEqual(@as(usize, 2), root.count());

    // The RFC's trailing zero is not represented in the `f64` value.
    const san_francisco = root.at(0) orelse return error.MissingElement;
    try std.testing.expectEqualStrings("SAN FRANCISCO", try string(san_francisco, "City"));
    try std.testing.expectEqualStrings("zip", try string(san_francisco, "precision"));
    try std.testing.expectEqual(@as(f64, 37.7668), try number(san_francisco, "Latitude"));
    try std.testing.expectEqual(@as(f64, -122.3959), try number(san_francisco, "Longitude"));
    try std.testing.expectEqualStrings("", try string(san_francisco, "Address"));

    const sunnyvale = root.at(1) orelse return error.MissingElement;
    try std.testing.expectEqualStrings("SUNNYVALE", try string(sunnyvale, "City"));
    try std.testing.expectEqual(@as(f64, 37.371991), try number(sunnyvale, "Latitude"));
    try std.testing.expectEqual(@as(f64, -122.02602), try number(sunnyvale, "Longitude"));
    try std.testing.expectEqualStrings("94085", try string(sunnyvale, "Zip"));
}

test "RFC 8259 section 13: the three one-value documents are one value each" {
    nativeReady();

    const cases = [_]struct { path: []const u8, kind: cjson.Type }{
        .{ .path = "testdata/rfc8259/13-value-boolean.json", .kind = .true },
        .{ .path = "testdata/rfc8259/13-value-number.json", .kind = .number },
        .{ .path = "testdata/rfc8259/13-value-string.json", .kind = .string },
    };
    for (cases) |case| {
        const bytes = try readFixture(std.testing.allocator, case.path);
        defer std.testing.allocator.free(bytes);
        var doc = try parseFixture(bytes);
        defer doc.deinit();

        const root = doc.rootValue();
        try std.testing.expectEqual(case.kind, root.kind());
        switch (case.kind) {
            .true => try std.testing.expectEqual(true, root.boolValue() orelse return error.NotABool),
            .number => try std.testing.expectEqual(@as(f64, 42), root.numberValue() orelse
                return error.NotANumber),
            .string => try std.testing.expectEqualStrings("Hello world!", root.stringValue() orelse
                return error.NotAString),
            else => return error.WrongFixture,
        }
        // cJSON reports zero children for scalar values.
        try std.testing.expectEqual(@as(usize, 0), root.count());
    }
}

test "every number in the grammar fixture parses to the double its own text denotes" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/values/number-grammar.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(@as(usize, 17), root.count());

    // Compare each parsed number with Zig's independent decimal parser.
    var text = bytes;
    var index: usize = 0;
    for (0..root.count()) |position| {
        const element = root.at(position) orelse return error.MissingElement;
        const value = element.numberValue() orelse return error.NotANumber;

        // Read tokens from the fixture to keep expected values independent.
        text = text[std.mem.findAny(u8, text, "-0123456789").?..];
        var end = text.len;
        for (text, 0..) |byte, at| {
            if (byte == ',' or byte == ']' or byte == '\n') {
                end = at;
                break;
            }
        }
        const token = text[0..end];
        text = text[end..];

        const expected = std.fmt.parseFloat(f64, token) catch return error.BadFixture;
        try std.testing.expectEqual(
            @as(u64, @bitCast(expected)),
            @as(u64, @bitCast(value)),
        );
        index += 1;
    }
    try std.testing.expectEqual(root.count(), index);

    // The sign bit distinguishes parsed `-0` from `0`.
    const negative_zero = root.at(0) orelse return error.MissingElement;
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(
        negative_zero.numberValue() orelse return error.NotANumber,
    )));
    const positive_zero = root.at(1) orelse return error.MissingElement;
    try std.testing.expectEqual(@as(u64, 0), @as(u64, @bitCast(
        positive_zero.numberValue() orelse return error.NotANumber,
    )));
}

test "printed numbers are the strings upstream's own test suite records" {
    nativeReady();

    // Expected output comes from upstream's print_number table (src/tests/print_number.c:65-101).
    const cases = [_]struct { input: [:0]const u8, printed: [:0]const u8 }{
        .{ .input = "0", .printed = "0" },
        .{ .input = "-1", .printed = "-1" },
        .{ .input = "-32768", .printed = "-32768" },
        .{ .input = "-2147483648", .printed = "-2147483648" },
        .{ .input = "1", .printed = "1" },
        .{ .input = "32767", .printed = "32767" },
        .{ .input = "2147483647", .printed = "2147483647" },
        .{ .input = "0.123", .printed = "0.123" },
        .{ .input = "1e-09", .printed = "1e-09" },
        .{ .input = "1000000000000", .printed = "1000000000000" },
        .{ .input = "1.23e+129", .printed = "1.23e+129" },
        .{ .input = "1.23e-126", .printed = "1.23e-126" },
        .{ .input = "3.1415926535897931", .printed = "3.1415926535897931" },
        .{ .input = "-0.0123", .printed = "-0.0123" },
        .{ .input = "-1e-09", .printed = "-1e-09" },
        .{ .input = "-1e+21", .printed = "-1e+21" },
        .{ .input = "-1.23e+129", .printed = "-1.23e+129" },
        .{ .input = "-1.23e-126", .printed = "-1.23e-126" },
    };

    for (cases) |case| {
        var doc = cjson.parse(case.input, .{}) catch {
            std.debug.print("tests.zig: upstream's own number did not parse: {s}\n", .{case.input});
            return error.FixtureDidNotParse;
        };
        defer doc.deinit();

        const printed = try cjson.print(doc.rootValue(), .compact);
        defer cjson.freePrinted(printed);
        try std.testing.expectEqualStrings(case.printed, printed);
    }

    // These cases pin largest-f64 formatting and the loss of negative zero.
    {
        var doc = try cjson.parse("1.7976931348623157e308", .{});
        defer doc.deinit();
        const printed = try cjson.print(doc.rootValue(), .compact);
        defer cjson.freePrinted(printed);
        try std.testing.expectEqualStrings("1.79769313486232e+308", printed);
    }
    {
        var doc = try cjson.parse("-0.0", .{});
        defer doc.deinit();
        const printed = try cjson.print(doc.rootValue(), .compact);
        defer cjson.freePrinted(printed);
        try std.testing.expectEqualStrings("0", printed);
    }
}

test "every escape in the string fixture decodes to the bytes RFC 8259 section 7 names" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/values/string-escapes.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(@as(usize, 15), root.count());

    // Expected bytes follow RFC 8259 section 7; the surrogate pair encodes a four-byte UTF-8 character.
    const cases = [_]struct { expected: []const u8 }{
        .{ .expected = "\"" },
        .{ .expected = "\\" },
        .{ .expected = "/" },
        .{ .expected = "\x08" },
        .{ .expected = "\x0c" },
        .{ .expected = "\n" },
        .{ .expected = "\r" },
        .{ .expected = "\t" },
        .{ .expected = "A" },
        .{ .expected = "\xc3\xa9" },
        .{ .expected = "\xe4\xb8\xad\xe6\x96\x87" },
        .{ .expected = "\xf0\x9d\x84\x9e" },
        .{ .expected = "\xf0\x9f\x98\x80" },
        .{ .expected = "\xc3\xbcber" },
        .{ .expected = "A" },
    };

    for (cases, 0..) |case, index| {
        const element = root.at(index) orelse return error.MissingElement;
        const value = element.stringValue() orelse return error.NotAString;
        try std.testing.expectEqualStrings(case.expected, value);
    }
}

test "a raw control character is accepted and comes back escaped" {
    nativeReady();
    // cJSON accepts unescaped control bytes and escapes them when printing.
    const bytes = try readFixture(std.testing.allocator, "testdata/values/unescaped-control-character.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    const value = try string(root, "a");
    try std.testing.expectEqual(@as(usize, 3), value.len);
    try std.testing.expectEqual(@as(u8, 'x'), value[0]);
    try std.testing.expectEqual(@as(u8, 0x01), value[1]);
    try std.testing.expectEqual(@as(u8, 'y'), value[2]);

    const printed = try cjson.print(root, .compact);
    defer cjson.freePrinted(printed);
    try std.testing.expectEqualStrings("{\"a\":\"x\\u0001y\"}", printed);
}

test "a leading zero is accepted and is not reported as an error" {
    nativeReady();
    // cJSON accepts the non-RFC leading zero as the number 1.
    const bytes = try readFixture(std.testing.allocator, "testdata/values/leading-zero.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    try std.testing.expectEqual(@as(f64, 1), try number(doc.rootValue(), "a"));
}

test "a repeated member name resolves to the first occurrence and all three survive" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/values/duplicate-keys.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    // Lookup returns the first match; parsed duplicate members remain in the tree.
    try std.testing.expectEqual(@as(usize, 3), root.count());
    try std.testing.expectEqual(@as(f64, 1), try number(root, "a"));
    try std.testing.expectEqual(@as(f64, 2), try number(root, "b"));

    const third = root.at(2) orelse return error.MissingElement;
    try std.testing.expectEqualStrings("a", third.memberName() orelse return error.MissingName);
    try std.testing.expectEqual(@as(f64, 3), third.numberValue() orelse return error.NotANumber);

    try std.testing.expectEqual(@as(f64, 1), root.at(0).?.numberValue() orelse return error.NotANumber);
    try std.testing.expectEqual(@as(f64, 2), root.at(1).?.numberValue() orelse return error.NotANumber);
}

test "member lookup folds case by default and does not when asked" {
    nativeReady();
    var doc = try cjson.parse("{\"Key\":1}", .{});
    defer doc.deinit();
    const root = doc.rootValue();

    const folded = root.field("key", .case_insensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(@as(f64, 1), folded.numberValue() orelse return error.NotANumber);
    try std.testing.expectEqual(@as(?cjson.Borrowed, null), root.field("key", .case_sensitive));
    const exact = root.field("Key", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(@as(f64, 1), exact.numberValue() orelse return error.NotANumber);
    try std.testing.expect(root.hasField("KEY"));
    try std.testing.expect(!root.hasField("other"));
}

test "each document no conforming parser accepts is refused at the offset upstream reports" {
    nativeReady();

    // Offsets follow upstream parser paths, not measurements (src/cJSON.c:827-1215).
    const cases = [_]struct { path: []const u8, offset: usize }{
        .{ .path = "testdata/malformed/01-trailing-comma-object.json", .offset = 7 },
        .{ .path = "testdata/malformed/02-single-quoted-string.json", .offset = 2 },
        .{ .path = "testdata/malformed/03-unquoted-key.json", .offset = 2 },
        .{ .path = "testdata/malformed/04-nan-literal.json", .offset = 5 },
        .{ .path = "testdata/malformed/05-leading-plus-number.json", .offset = 5 },
        .{ .path = "testdata/malformed/07-missing-colon.json", .offset = 5 },
        .{ .path = "testdata/malformed/08-unterminated-string.json", .offset = 6 },
        .{ .path = "testdata/malformed/09-empty-input.json", .offset = 0 },
    };

    for (cases) |case| {
        const bytes = try readFixture(std.testing.allocator, case.path);
        defer std.testing.allocator.free(bytes);

        try std.testing.expectError(cjson.ParseError.ParseFailed, cjson.parseBytes(bytes, .{}));
        const offset = cjson.parseErrorOffset(bytes) orelse {
            std.debug.print("tests.zig: no error offset for {s}\n", .{case.path});
            return error.NoErrorOffset;
        };
        if (offset != case.offset) {
            std.debug.print(
                "tests.zig: {s}: error offset {d}, expected {d}\n",
                .{ case.path, offset, case.offset },
            );
            return error.WrongErrorOffset;
        }
        try std.testing.expect(offset <= bytes.len);
    }
}

test "a successful parse leaves no error position behind" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/rfc8259/13-value-number.json");
    defer std.testing.allocator.free(bytes);

    var doc = try parseFixture(bytes);
    defer doc.deinit();

    // A successful parse clears cJSON's process-wide error pointer (src/cJSON.c:1147-1150).
    try std.testing.expectEqual(@as(?usize, null), cjson.parseErrorOffset(bytes));
}

test "a counted buffer cannot be asked for a strict parse it cannot honour" {
    nativeReady();
    try std.testing.expectError(
        cjson.ParseError.NullTerminatedInputRequired,
        cjson.parseBytes("{\"a\":1}", .{ .require_null_terminated = true }),
    );
}

test "trailing content is accepted by a lax parse and refused by a strict one" {
    nativeReady();
    const text: [:0]const u8 = "{\"a\":1} trailing";

    {
        var doc = try cjson.parse(text, .{});
        defer doc.deinit();
        try std.testing.expectEqual(@as(usize, 1), doc.rootValue().count());
    }
    {
        var doc = cjson.parse(text, .{ .require_null_terminated = true }) catch |err| switch (err) {
            cjson.ParseError.ParseFailed => return,
            else => return err,
        };
        doc.deinit();
        return error.TrailingContentWasAccepted;
    }
}

test "nesting is accepted below the header's limit and refused above it" {
    nativeReady();

    // cJSON rejects nesting beyond CJSON_NESTING_LIMIT (src/cJSON.h:136-138).
    for ([_]usize{ 32, 64 }) |depth| {
        const path = try std.testing.allocator.print(
            "testdata/values/nesting-{d}.json",
            .{depth},
        );
        defer std.testing.allocator.free(path);
        const bytes = try readFixture(std.testing.allocator, path);
        defer std.testing.allocator.free(bytes);

        var doc = try parseFixture(bytes);
        defer doc.deinit();

        var node = doc.rootValue();
        for (0..depth) |_| {
            node = node.field("a", .case_sensitive) orelse return error.MissingMember;
        }
        const leaf = node.field("leaf", .case_sensitive) orelse return error.MissingMember;
        try std.testing.expectEqualStrings("leaf", leaf.memberName() orelse return error.MissingName);
        try std.testing.expectEqual(@as(f64, 1), leaf.numberValue() orelse return error.NotANumber);
    }

    {
        const bytes = try readFixture(std.testing.allocator, "testdata/values/nesting-2048.json");
        defer std.testing.allocator.free(bytes);
        try std.testing.expectError(cjson.ParseError.ParseFailed, cjson.parseBytes(bytes, .{}));
        const offset = cjson.parseErrorOffset(bytes) orelse return error.NoErrorOffset;
        try std.testing.expect(offset <= bytes.len);
    }
}

test "a 631 KB document parses, and the counts and fields read out of it are the recorded ones" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/large/twitter.json");
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 631515), bytes.len);

    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(cjson.Type.object, root.kind());
    try std.testing.expectEqual(@as(usize, 2), root.count());

    const metadata = root.field("search_metadata", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(@as(f64, 100), try number(metadata, "count"));
    try std.testing.expectEqual(@as(f64, 0), try number(metadata, "since_id"));

    // Binary64 rounds numeric `max_id`; `max_id_str` preserves its exact digits.
    try std.testing.expectEqual(@as(f64, 505874924095815700.0), try number(metadata, "max_id"));
    try std.testing.expectEqualStrings("505874924095815681", try string(metadata, "max_id_str"));

    const statuses = root.field("statuses", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(cjson.Type.array, statuses.kind());
    try std.testing.expectEqual(@as(usize, 100), statuses.count());

    const first = statuses.at(0) orelse return error.MissingElement;
    try std.testing.expectEqual(@as(f64, 505874924095815681.0), try number(first, "id"));
    try std.testing.expectEqual(@as(f64, 0), try number(first, "retweet_count"));
    try std.testing.expectEqual(@as(f64, 0), try number(first, "favorite_count"));
    try std.testing.expectEqualStrings("ayuu0123", try string(first.field("user", .case_sensitive) orelse
        return error.MissingMember, "screen_name"));

    const text = try string(first, "text");
    try std.testing.expect(std.mem.startsWith(u8, text, "@aym0566x "));
    try std.testing.expect(std.mem.find(u8, text, "\xe5\x90\x8d") != null);
}

test "detaching a member hands it to the caller and shortens the document" {
    nativeReady();
    var doc = try cjson.parse("{\"a\":1,\"b\":2}", .{});
    defer doc.deinit();

    var root = doc.rootValue();
    try std.testing.expectEqual(@as(usize, 2), root.count());

    const detached = root.detachField("a", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(@as(usize, 1), root.count());
    try std.testing.expectEqual(@as(f64, 1), detached.borrow().numberValue() orelse
        return error.NotANumber);
    try std.testing.expectEqual(@as(?cjson.Borrowed, null), root.field("a", .case_sensitive));

    const printed = try cjson.print(root, .compact);
    defer cjson.freePrinted(printed);
    try std.testing.expectEqualStrings("{\"b\":2}", printed);

    detached.deinit();
}

test "deleting a member removes it and releases it" {
    nativeReady();
    var doc = try cjson.parse("{\"a\":1,\"b\":2,\"c\":3}", .{});
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(@as(usize, 3), root.count());
    root.deleteField("b", .case_sensitive);
    try std.testing.expectEqual(@as(usize, 2), root.count());
    try std.testing.expectEqual(@as(?cjson.Borrowed, null), root.field("b", .case_sensitive));

    const printed = try cjson.print(root, .compact);
    defer cjson.freePrinted(printed);
    try std.testing.expectEqualStrings("{\"a\":1,\"c\":3}", printed);
}

test "replacing a member takes the new value and releases the old one" {
    nativeReady();
    var doc = try cjson.parse("{\"a\":1}", .{});
    defer doc.deinit();

    const root = doc.rootValue();
    const replacement = try cjson.createString("seven");
    try root.replaceField("a", replacement, .case_sensitive);

    try std.testing.expectEqual(@as(usize, 1), root.count());
    try std.testing.expectEqualStrings("seven", try string(root, "a"));
}

test "an array built through the facade prints in the order it was appended" {
    nativeReady();
    const array = try cjson.createArray();
    try array.borrow().append(try cjson.createNumber(1));
    try array.borrow().append(try cjson.createNumber(2));
    try array.borrow().append(try cjson.createString("three"));
    try array.borrow().append(try cjson.createBool(true));
    try array.borrow().append(try cjson.createNull());
    defer array.deinit();

    const printed = try cjson.print(array.borrow(), .compact);
    defer cjson.freePrinted(printed);
    try std.testing.expectEqualStrings("[1,2,\"three\",true,null]", printed);

    // cJSON formats arrays with comma spaces but no indentation (src/cJSON.c:1590-1649).
    const formatted = try cjson.print(array.borrow(), .formatted);
    defer cjson.freePrinted(formatted);
    try std.testing.expectEqualStrings("[1, 2, \"three\", true, null]", formatted);
}

test "inserting at an index shifts the elements to its right" {
    nativeReady();
    const array = try cjson.createArray();
    try array.borrow().append(try cjson.createNumber(1));
    try array.borrow().append(try cjson.createNumber(3));
    try array.borrow().insertAt(1, try cjson.createNumber(2));
    defer array.deinit();

    try std.testing.expectEqual(@as(usize, 3), array.borrow().count());
    const printed = try cjson.print(array.borrow(), .compact);
    defer cjson.freePrinted(printed);
    try std.testing.expectEqualStrings("[1,2,3]", printed);
}

test "printing into a buffer too small reports it rather than truncating silently" {
    nativeReady();
    var doc = try cjson.parse("{\"a\":[1,2,3]}", .{});
    defer doc.deinit();

    var small: [8]u8 = undefined;
    try std.testing.expect(!cjson.printInto(doc.rootValue(), &small, .compact));

    var roomy: [64]u8 = undefined;
    try std.testing.expect(cjson.printInto(doc.rootValue(), &roomy, .compact));
    const written = std.mem.findScalar(u8, &roomy, 0).?;
    try std.testing.expectEqualStrings("{\"a\":[1,2,3]}", roomy[0..written]);
}

test "comparison uses the documented numeric tolerance, not bit equality" {
    nativeReady();

    var tenth = try cjson.parse("0.1", .{});
    defer tenth.deinit();
    var fifth = try cjson.parse("0.2", .{});
    defer fifth.deinit();
    // Parsed operands test runtime binary64 arithmetic.
    var sum = try cjson.parse("0.30000000000000004", .{});
    defer sum.deinit();
    var third = try cjson.parse("0.3", .{});
    defer third.deinit();

    // Parsing avoids comptime arithmetic, which can round differently.
    const sum_bits = @as(u64, @bitCast(
        tenth.rootValue().numberValue().? + fifth.rootValue().numberValue().?,
    ));
    const third_bits = @as(u64, @bitCast(third.rootValue().numberValue().?));
    try std.testing.expect(sum_bits != third_bits);
    try std.testing.expect(sum.rootValue().equal(third.rootValue(), .case_sensitive));
    try std.testing.expect(third.rootValue().equal(sum.rootValue(), .case_sensitive));

    try std.testing.expect(!tenth.rootValue().equal(fifth.rootValue(), .case_sensitive));

    var left = try cjson.parse("{\"a\":1,\"b\":2}", .{});
    defer left.deinit();
    var right = try cjson.parse("{\"b\":2,\"a\":1}", .{});
    defer right.deinit();
    try std.testing.expect(left.rootValue().equal(right.rootValue(), .case_sensitive));

    var subset = try cjson.parse("{\"a\":1}", .{});
    defer subset.deinit();
    try std.testing.expect(!left.rootValue().equal(subset.rootValue(), .case_sensitive));
}

test "a recursive duplicate is an independent tree" {
    nativeReady();
    var doc = try cjson.parse("{\"a\":{\"b\":[1,2]}}", .{});
    defer doc.deinit();

    const copy = try cjson.duplicate(doc.rootValue(), true);
    defer copy.deinit();

    // A recursive duplicate copies the full tree (src/cJSON.c:2769-2790).
    try std.testing.expect(doc.rootValue().equal(copy.borrow(), .case_sensitive));
    try std.testing.expect(copy.borrow().raw() != doc.rootValue().raw());

    const copied_a = copy.borrow().field("a", .case_sensitive) orelse return error.MissingMember;
    try copied_a.replaceField("b", try cjson.createNumber(99), .case_sensitive);

    const copied_b = copied_a.field("b", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(cjson.Type.number, copied_b.kind());
    try std.testing.expectEqual(@as(f64, 99), copied_b.numberValue() orelse return error.NotANumber);

    const original_a = doc.rootValue().field("a", .case_sensitive) orelse return error.MissingMember;
    const original_b = original_a.field("b", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(@as(usize, 2), original_b.count());
    try std.testing.expectEqual(@as(f64, 1), original_b.at(0).?.numberValue() orelse
        return error.NotANumber);
    try std.testing.expectEqual(@as(f64, 2), original_b.at(1).?.numberValue() orelse
        return error.NotANumber);
}
