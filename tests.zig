//! Behavioural tests for the cJSON facade.
//!
//! ## What the expectations are
//!
//! Four kinds, and they are kept apart on purpose:
//!
//!   * **RFC 8259.** The `testdata/rfc8259/` documents are the examples in
//!     section 13 of RFC 8259 (Bray, *The JavaScript Object Notation (JSON)
//!     Data Interchange Format*, December 2017), transcribed verbatim. The
//!     expected values in the first tests are the ones the RFC itself prints, so
//!     agreeing with them is agreeing with the specification rather than with
//!     this binding. The transcription, the six-space indent the RFC's text
//!     formatting adds, and the digests are in UPSTREAM.md.
//!   * **Upstream's own recorded output.** The printed-number table below is
//!     `src/tests/print_number.c:65-101`, the reference implementation's own
//!     expectations for `print_number`. That is interoperability with a
//!     reference implementation rather than a round trip through this build.
//!   * **The documented behaviour of this configuration.** The rejected inputs
//!     carry the byte offset upstream reports for them, each derived from the
//!     line references given, and the nesting test uses the limit the header
//!     states. Those are behavioural boundaries, not version pins.
//!   * **Independent arithmetic.** Where a number is involved the expected
//!     `f64` is either the RFC's own digits or the result of Zig's own
//!     `std.fmt.parseFloat`, which is a different implementation from cJSON's
//!     `strtod` (`src/cJSON.c:378`). Nothing here asserts "the parse agreed
//!     with the print".
//!
//! The two fixtures in `testdata/values/` that RFC 8259 forbids and this parser
//! accepts -- `leading-zero.json` and `unescaped-control-character.json` -- are
//! tested for exactly what upstream's source says it does with them, with the
//! deviation named. They are not tested as if they were accepted by
//! specification.
//!
//! ## What is deliberately absent
//!
//! No test pins `cJSON_Version`, a constant, a default, or the presence of a
//! declaration; those belong to the provenance and licence gates. No test
//! compares a forwarding accessor with a raw member. Every public method on the
//! facade is called from this file, which is what makes building the test binary
//! a real check of the facade rather than of an unreferenced C archive.
//!
//! ## The provider, in a runtime-loading build
//!
//! A `-Druntime` build links no archive, so every test below reaches the library
//! through the loader and nothing works until a provider has been named. It is
//! named by `CJSON_PROVIDER`, an absolute path to a shared object exporting the
//! `cJSON_*` API. Nothing is loaded by default and no other file is tried: a
//! build that was not told which file to load stops with the variable's name
//! rather than reporting a failure that says nothing about the reason. In a
//! linked build the variable is never read.

const std = @import("std");
const cjson = @import("cjson");

/// Where the build put the fixture corpus. Relative to the build root, which is
/// the working directory a `Step.Run` with no explicit cwd inherits.
const paths = @import("cjson_paths");

/// A shared object exporting the `cJSON_*` API, named by the environment in a
/// runtime-loading build.
const provider_variable = "CJSON_PROVIDER";

/// The largest fixture in `testdata/`. It is `testdata/large/twitter.json`,
/// 631,515 bytes; the limit is a bound on this test's own read, chosen above it
/// so a truncated fixture is a failure here rather than a silent shorter parse.
const fixture_limit: std.Io.Limit = .limited(1 << 20);

/// Make the native library usable, once, before a test calls the facade.
///
/// Safe to call from every test: the loader's contract makes the same request
/// idempotent and keeps the handle to the end of the process, so `loadedSource`
/// is what makes the second and later calls free of work.
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

/// Read one fixture.
///
/// The fixtures are counted buffers, not NUL-terminated strings, so they are
/// parsed with `parseBytes` throughout. That is the entry point a caller with a
/// mapped file or a network buffer has to use anyway, and it is the one whose
/// length argument the tests then depend on.
fn readFixture(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, fixture_limit);
}

/// Parse a fixture, with a message naming the file if it does not parse.
fn parseFixture(bytes: []const u8) !cjson.Document {
    return cjson.parseBytes(bytes, .{}) catch {
        std.debug.print("tests.zig: fixture did not parse: {s}\n", .{bytes[0..@min(bytes.len, 80)]});
        return error.FixtureDidNotParse;
    };
}

/// The value of a member that must be a number, with the two failures named.
fn number(doc: cjson.Borrowed, name: [:0]const u8) !f64 {
    const member = doc.field(name, .case_sensitive) orelse return error.MissingMember;
    return member.numberValue() orelse return error.NotANumber;
}

/// The value of a member that must be a string, with the two failures named.
fn string(doc: cjson.Borrowed, name: [:0]const u8) ![]const u8 {
    const member = doc.field(name, .case_sensitive) orelse return error.MissingMember;
    return member.stringValue() orelse return error.NotAString;
}

// ---------------------------------------------------------------------------
// RFC 8259 section 13
// ---------------------------------------------------------------------------

test "RFC 8259 section 13: the example object keeps every member and value the RFC prints" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/rfc8259/13-object.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(cjson.Type.object, root.kind());
    // The RFC's example object has exactly one member at the top level,
    // `Image`, and every value the RFC prints is inside it
    // (`testdata/rfc8259/13-object.json:2-13`).
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

    // The one member name the RFC spells with a space before its colon.
    try std.testing.expectEqualStrings("Animated", image.at(4).?.memberName() orelse
        return error.MissingName);

    const thumbnail = image.field("Thumbnail", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqualStrings(
        "http://www.example.com/image/481989943",
        try string(thumbnail, "Url"),
    );
    try std.testing.expectEqual(@as(f64, 125), try number(thumbnail, "Height"));
    try std.testing.expectEqual(@as(f64, 100), try number(thumbnail, "Width"));

    // Four integers, in order. The RFC writes them as `[116, 943, 234, 38793]`.
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

    // The RFC prints `-122.026020` for the second longitude. A `double` has no
    // trailing zero, and the value is the one the RFC's digits denote: this is
    // the nearest double to -122.02602 and nothing else.
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
        // A scalar has no children, and upstream counts them by walking the
        // chain rather than by looking at the type (`src/cJSON.c:1884-1905`).
        try std.testing.expectEqual(@as(usize, 0), root.count());
    }
}

// ---------------------------------------------------------------------------
// Numbers
// ---------------------------------------------------------------------------

test "every number in the grammar fixture parses to the double its own text denotes" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/values/number-grammar.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(@as(usize, 17), root.count());

    // Walk the fixture's own text and parse it again with Zig's parser, which
    // shares no code with cJSON's `strtod` (`src/cJSON.c:378`). The comparison
    // is on bits: an equal-looking decimal can round to two different doubles
    // and this is where that would show up.
    var text = bytes;
    var index: usize = 0;
    for (0..root.count()) |position| {
        const element = root.at(position) orelse return error.MissingElement;
        const value = element.numberValue() orelse return error.NotANumber;

        // The fixture is one number per line, between `[`, a comma or `]` and
        // the newline. Reading the token out of the fixture rather than out of a
        // second table is what keeps the two halves independent.
        text = text[std.mem.findAny(u8, text, "-0123456789").? ..];
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

    // `-0` is in that fixture because its sign is the only thing that
    // distinguishes it from `0`, and the sign is in the bit pattern.
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

    // This table is `src/tests/print_number.c:65-101`, copied out of the
    // reference implementation's own expectations. It is not this build
    // comparing itself with itself: those strings were recorded by upstream, for
    // its own `print_number`, and they are what the formatter has to produce.
    //
    // Each row is reached by parsing the number as a whole document and
    // printing it with `cJSON_PrintUnformatted`, which routes a bare number
    // through the same `print_number` (`src/cJSON.c:1456-1457`).
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

    // Two rows this build has to answer for itself, because they are what the
    // `test1`/`test7` fixtures contain and neither is in upstream's table:
    // the exact form of the largest double, and the fact that `-0` prints as
    // `0`. The first is `print_number`'s 15-digit branch
    // (`src/cJSON.c:618-621`): `%1.15g` of the largest double is
    // `1.79769313486232e+308`, re-reading that does not give the original
    // double back, but `compare_double`'s tolerance (`src/cJSON.c:584-588`)
    // accepts it, so the 17-digit branch at `src/cJSON.c:623-625` is never
    // taken. The second one is `print_number`'s integer branch
    // (`src/cJSON.c:611-614`) applied to a value whose `valueint` is 0, and
    // `-0.0 == 0.0` is true, so the sign does not survive the print.
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

// ---------------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------------

test "every escape in the string fixture decodes to the bytes RFC 8259 section 7 names" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/values/string-escapes.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    try std.testing.expectEqual(@as(usize, 15), root.count());

    // The expectations are the decoded bytes of the escape, written out from the
    // grammar in RFC 8259 section 7 and from the code point each escape names.
    // `\ud834\udd1e` is the G clef, the example the RFC gives for a character
    // outside the Basic Multilingual Plane (section 7), and its UTF-8 form is
    // four bytes; `\u4e2d\u6587` is two three-byte forms.
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
    // RFC 8259 section 7 requires a control character in a string to be
    // escaped, so this document is not conforming. This parser accepts it:
    // `parse_string` copies every byte that is not a backslash, with no check
    // on its value (`src/cJSON.c:867-873`). The deviation is the point of the
    // test, and it is pinned in both directions -- accepted here, and re-emitted
    // as `\u0001`, because `print_string_ptr` escapes every byte below 32 with
    // `sprintf("u%04x", byte)` (`src/cJSON.c:991-998`, `:1058`).
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
    // RFC 8259 section 6 forbids leading zeros; `parse_value` admits `-` or a
    // digit (`src/cJSON.c:1399`), `parse_number` scans the whole
    // `0-9 + - e E .` run (`src/cJSON.c:325-354`), and `strtod` consumes `01` as
    // one decimal number (`src/cJSON.c:378`). The value is 1.
    const bytes = try readFixture(std.testing.allocator, "testdata/values/leading-zero.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    try std.testing.expectEqual(@as(f64, 1), try number(doc.rootValue(), "a"));
}

// ---------------------------------------------------------------------------
// Object shape
// ---------------------------------------------------------------------------

test "a repeated member name resolves to the first occurrence and all three survive" {
    nativeReady();
    const bytes = try readFixture(std.testing.allocator, "testdata/values/duplicate-keys.json");
    defer std.testing.allocator.free(bytes);
    var doc = try parseFixture(bytes);
    defer doc.deinit();

    const root = doc.rootValue();
    // Three members, not two: `get_object_item` walks the chain and stops at
    // the first match (`src/cJSON.c:1945-1965`), but nothing deduplicates on
    // the way in, so every name that was parsed is still in the document.
    try std.testing.expectEqual(@as(usize, 3), root.count());
    try std.testing.expectEqual(@as(f64, 1), try number(root, "a"));
    try std.testing.expectEqual(@as(f64, 2), try number(root, "b"));

    const third = root.at(2) orelse return error.MissingElement;
    try std.testing.expectEqualStrings("a", third.memberName() orelse return error.MissingName);
    try std.testing.expectEqual(@as(f64, 3), third.numberValue() orelse return error.NotANumber);

    // Both names are reachable by index; only the first is reachable by name.
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
    // `cJSON_HasObjectItem` is the folded predicate (`src/cJSON.h:180`), and it
    // is what this answers; a case-sensitive caller has `field` above.
    try std.testing.expect(root.hasField("KEY"));
    try std.testing.expect(!root.hasField("other"));
}

// ---------------------------------------------------------------------------
// Malformed input
// ---------------------------------------------------------------------------

test "each document no conforming parser accepts is refused at the offset upstream reports" {
    nativeReady();

    // Every offset below is derived from the parse path, not measured:
    //
    //  * `{"a":1,}` -- the second loop iteration of `parse_object`
    //    (`src/cJSON.c:1685-1740`) calls `parse_string` on the `}` at index 7,
    //    which fails its first check; `parse_string`'s failure path puts the
    //    offset one past that character (`src/cJSON.c:940-943`), which is the
    //    end of the buffer, and `cJSON_ParseWithLengthOpts` clamps a position
    //    that ran off the end to the last byte (`src/cJSON.c:1201-1208`). So 7.
    //  * `{'a':'b'}` -- the value is an object, so `parse_value` takes its `{`
    //    branch (`src/cJSON.c:1409-1412`) and `parse_object` asks
    //    `parse_string` for the name at index 1 (`src/cJSON.c:1714-1719`).
    //    `parse_string` fails its first check on the `'`
    //    (`src/cJSON.c:827-830`), and its failure path records
    //    `input_pointer`, which is one past the opening quote
    //    (`src/cJSON.c:821`, `:940-943`): 2.
    //  * `{a:1}` -- `parse_object` calls `parse_string` at index 1, which fails
    //    immediately and reports one past it: 2.
    //  * `{"a":NaN}` and `{"a":+1}` -- the name and the colon are consumed and
    //    `parse_value` matches nothing for `N` or `+`, which is index 5.
    //  * `{"a" 1}` -- after the name, whitespace is skipped to index 5 and the
    //    colon check fails (`src/cJSON.c:1726-1729`): 5.
    //  * `{"a":"b}` -- the value string scans for a closing quote from one past
    //    its own opening one and runs off the end without finding one
    //    (`src/cJSON.c:836-854`); the failure path records `input_pointer`,
    //    which is one past that opening quote (`src/cJSON.c:821`, `:940-943`),
    //    so 6. The `}` at index 7 is never reached, and nothing is clamped
    //    because 6 < 8.
    //  * an empty buffer -- rejected before parsing (`src/cJSON.c:1151-1154`)
    //    with position 0.
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

    // `cJSON_ParseWithLengthOpts` clears both halves of the global error record
    // before it parses anything (`src/cJSON.c:1147-1150`), so after a success the
    // answer is null rather than a stale position from an earlier failure.
    try std.testing.expectEqual(@as(?usize, null), cjson.parseErrorOffset(bytes));
}

test "a counted buffer cannot be asked for a strict parse it cannot honour" {
    nativeReady();
    // `cJSON_ParseWithLength` forwards `require_null_terminated` as 0
    // (`src/cJSON.c:1229`), so the request is refused rather than dropped: a
    // caller who asked for strictness must not silently get laxness.
    try std.testing.expectError(
        cjson.ParseError.NullTerminatedInputRequired,
        cjson.parseBytes("{\"a\":1}", .{ .require_null_terminated = true }),
    );
}

test "trailing content is accepted by a lax parse and refused by a strict one" {
    nativeReady();
    const text: [:0]const u8 = "{\"a\":1} trailing";

    {
        // Without the flag, upstream stops at the end of the first value and
        // never looks at what follows (`src/cJSON.c:1174-1181`).
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

// ---------------------------------------------------------------------------
// Depth and scale
// ---------------------------------------------------------------------------

test "nesting is accepted below the header's limit and refused above it" {
    nativeReady();

    // `CJSON_NESTING_LIMIT` is 1000 (`src/cJSON.h:136-138`), checked before each
    // level of array or object (`src/cJSON.c:1497-1501`, `:1657-1661`), so a
    // document nested deeper than that is refused rather than risking the stack.
    for ([_]usize{ 32, 64 }) |depth| {
        const path = try std.fmt.allocPrint(
            std.testing.allocator,
            "testdata/values/nesting-{d}.json",
            .{depth},
        );
        defer std.testing.allocator.free(path);
        const bytes = try readFixture(std.testing.allocator, path);
        defer std.testing.allocator.free(bytes);

        var doc = try parseFixture(bytes);
        defer doc.deinit();

        // Walk down exactly as deep as the document is nested -- the fixture is
        // `depth` objects named `a` around one object holding `leaf` -- and
        // then one step further, onto the member itself, which is the value
        // that carries the name and the number asserted below.
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

    // The file carries the same identifier twice, once as a number and once as a
    // string, and a `double` cannot hold all of it. `max_id` is written as
    // 505874924095815700, which is what 505874924095815681 rounds to in binary64
    // -- two units of the last digit away -- while `max_id_str` is the exact
    // digits. A parser that silently rounded both the same way, or that lost the
    // string, would fail one half of this.
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

    // Multi-byte UTF-8 survives the parse as bytes, and the fixture's first
    // record begins with an ASCII handle followed by Japanese text.
    const text = try string(first, "text");
    try std.testing.expect(std.mem.startsWith(u8, text, "@aym0566x "));
    try std.testing.expect(std.mem.find(u8, text, "\xe5\x90\x8d") != null);
}

// ---------------------------------------------------------------------------
// Ownership and mutation
// ---------------------------------------------------------------------------

test "detaching a member hands it to the caller and shortens the document" {
    nativeReady();
    var doc = try cjson.parse("{\"a\":1,\"b\":2}", .{});
    defer doc.deinit();

    var root = doc.rootValue();
    try std.testing.expectEqual(@as(usize, 2), root.count());

    // The ownership transition: what comes back has to be released by the
    // caller, because `cJSON_DetachItemFromObject` removes the node from the
    // chain and returns it without freeing it (`src/cJSON.h:239-245`).
    const detached = root.detachField("a", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(@as(usize, 1), root.count());
    try std.testing.expectEqual(@as(f64, 1), detached.borrow().numberValue() orelse
        return error.NotANumber);
    try std.testing.expectEqual(@as(?cjson.Borrowed, null), root.field("a", .case_sensitive));

    // The document no longer knows about it, so it can print without it.
    const printed = try cjson.print(root, .compact);
    defer cjson.freePrinted(printed);
    try std.testing.expectEqualStrings("{\"b\":2}", printed);

    // And releasing it here is the only release it needs.
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

    // `print_array` emits no newlines and no indentation at all
    // (`src/cJSON.c:1590-1649`): the only difference between the two formatters
    // is a space after each comma. Indentation belongs to `print_object`
    // (`src/cJSON.c:1791-1812`), and it is one tab per level, not spaces.
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
    // `cJSON_PrintPreallocated` NUL-terminates what it wrote
    // (`src/cJSON.c:1360-1361`), so the bytes before the NUL are the document.
    const written = std.mem.findScalar(u8, &roomy, 0).?;
    try std.testing.expectEqualStrings("{\"a\":[1,2,3]}", roomy[0..written]);
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

test "comparison uses the documented numeric tolerance, not bit equality" {
    nativeReady();

    var tenth = try cjson.parse("0.1", .{});
    defer tenth.deinit();
    var fifth = try cjson.parse("0.2", .{});
    defer fifth.deinit();
    // The document the sum belongs in. `0.1 + 0.2` is not `0.3` in binary64,
    // and it is not `0.1` either, which is what makes the comparison below a
    // comparison of a sum against `0.3` at all.
    var sum = try cjson.parse("0.30000000000000004", .{});
    defer sum.deinit();
    var third = try cjson.parse("0.3", .{});
    defer third.deinit();

    // 0.1 + 0.2 is not 0.3 as a double: their bit patterns differ
    // (0x3FD3333333333334 against 0x3FD3333333333333). The two operands are
    // read out of parsed documents rather than written as comptime literals,
    // because Zig evaluates a comptime `0.1 + 0.2` in wider arithmetic where it
    // rounds to the same binary64 as `0.3`: the difference asserted here is a
    // fact about the arithmetic a running program performs.
    const sum_bits = @as(u64, @bitCast(
        tenth.rootValue().numberValue().? + fifth.rootValue().numberValue().?,
    ));
    const third_bits = @as(u64, @bitCast(third.rootValue().numberValue().?));
    try std.testing.expect(sum_bits != third_bits);
    // `compare_double` accepts them anyway, because the difference
    // (5.551115123125783e-17) is within `DBL_EPSILON` times the larger
    // magnitude (6.661338147750939e-17) (`src/cJSON.c:584-588`).
    try std.testing.expect(sum.rootValue().equal(third.rootValue(), .case_sensitive));
    try std.testing.expect(third.rootValue().equal(sum.rootValue(), .case_sensitive));

    // Two numbers that are not close are still not equal.
    try std.testing.expect(!tenth.rootValue().equal(fifth.rootValue(), .case_sensitive));

    // And an object comparison is by member name, not by position: the fixture's
    // keys are in a different order in each document and the answer is still
    // equal, because `cJSON_Compare` looks each member up by name in both
    // directions (`src/cJSON.c:3139-3174`).
    var left = try cjson.parse("{\"a\":1,\"b\":2}", .{});
    defer left.deinit();
    var right = try cjson.parse("{\"b\":2,\"a\":1}", .{});
    defer right.deinit();
    try std.testing.expect(left.rootValue().equal(right.rootValue(), .case_sensitive));

    var subset = try cjson.parse("{\"a\":1}", .{});
    defer subset.deinit();
    try std.testing.expect(!left.rootValue().equal(subset.rootValue(), .case_sensitive));
}

// ---------------------------------------------------------------------------
// Duplication
// ---------------------------------------------------------------------------

test "a recursive duplicate is an independent tree" {
    nativeReady();
    var doc = try cjson.parse("{\"a\":{\"b\":[1,2]}}", .{});
    defer doc.deinit();

    const copy = try cjson.duplicate(doc.rootValue(), true);
    defer copy.deinit();

    // A recursive duplicate starts out equal to its original and shares no node
    // with it (`src/cJSON.c:2769-2790`).
    try std.testing.expect(doc.rootValue().equal(copy.borrow(), .case_sensitive));
    try std.testing.expect(copy.borrow().raw() != doc.rootValue().raw());

    // The copy is a separate tree, so changing one does not change the other.
    // The change goes through the owning type's own methods, which is what
    // makes this a statement about the copy rather than about the original.
    const copied_a = copy.borrow().field("a", .case_sensitive) orelse return error.MissingMember;
    try copied_a.replaceField("b", try cjson.createNumber(99), .case_sensitive);

    const copied_b = copied_a.field("b", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(cjson.Type.number, copied_b.kind());
    try std.testing.expectEqual(@as(f64, 99), copied_b.numberValue() orelse return error.NotANumber);

    // The original still holds the tree it was parsed from.
    const original_a = doc.rootValue().field("a", .case_sensitive) orelse return error.MissingMember;
    const original_b = original_a.field("b", .case_sensitive) orelse return error.MissingMember;
    try std.testing.expectEqual(@as(usize, 2), original_b.count());
    try std.testing.expectEqual(@as(f64, 1), original_b.at(0).?.numberValue() orelse
        return error.NotANumber);
    try std.testing.expectEqual(@as(f64, 2), original_b.at(1).?.numberValue() orelse
        return error.NotANumber);
}