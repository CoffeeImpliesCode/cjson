// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers, NOTICE.md for the
// terms that cover everything in src/, and UPSTREAM.md for the pin.
//!
//! Build for the cJSON Zig package.
//!
//! cJSON 1.7.19 is one C file and one header. Upstream's own build definition
//! says so: `src/CMakeLists.txt:101` is `set(SOURCES cJSON.c)` and
//! `src/CMakeLists.txt:117` adds exactly that one source to `add_library`; the
//! only other `.c` in the release, `src/cJSON_Utils.c`, belongs to a *second*
//! library target upstream builds separately (`src/CMakeLists.txt:213-221`,
//! `libcjson-utils`). This package compiles the first one and ships the second
//! unmodified, uncompiled; UPSTREAM.md, "What is compiled and what is not",
//! states that boundary and why it is upstream's and not this fork's.
//!
//! Nothing here runs CMake, make or any configure script, and nothing is
//! downloaded: the complete release tree is vendored under `src/`, and this file
//! owns every compile flag, every installed path and every step.
//!
//! ## Steps
//!
//!   (default)  install `libcjson` in the selected linkage, the upstream public
//!              header, the pkg-config record and the licence material, and
//!              compile the smoke example
//!   test       build the behavioural tests for the selected target and hand
//!              them to a run step, for every target including the host
//!   smoke      run the smoke example, which checks its own answers
//!   check      compile the native core, the translated header, the facade, the
//!              tests and the example for all six required targets without
//!              running any of them; an explicit `-Dtarget` narrows this to
//!              that one target
//!
//! `test` builds the same graph for whichever target was selected and hands the
//! binary to a `Run` step unconditionally. Whether that binary can be executed
//! -- natively, through an external executor, or not at all -- belongs to
//! whoever drives the build; `cross-test.profile.sh` is this package's settings
//! half of that arrangement.
//!
//! ## Options
//!
//!   -Dlinkage=static   a static archive, `libcjson.a`. The default.
//!   -Dlinkage=dynamic  a real shared object: `libcjson.so.1.7.19` with
//!                      `libcjson.so.1` and `libcjson.so` beside it, or
//!                      `cjson.dll` with its import library on Windows-gnu.
//!                      The version is upstream's own: `src/CMakeLists.txt:12`
//!                      is `set(CJSON_VERSION_SO 1)` and `:170` applies it as
//!                      `SOVERSION`, with `VERSION "${PROJECT_VERSION}"` at
//!                      `:169`, so upstream's shared object is
//!                      `libcjson.so.1.7.19` with soname `libcjson.so.1`. This
//!                      package does not invent a second ABI number.
//!   -Druntime=true     resolve the library's entry points at run time instead
//!                      of linking them. The facade keeps the same translated
//!                      header and the same public types; each native function
//!                      becomes a dispatch through one process-lifetime table
//!                      that an explicit `load(source)` fills, and the module
//!                      links no archive. Independent of `-Dlinkage`, which
//!                      still decides which artifact this build delivers and
//!                      installs -- under `-Druntime` that artifact is what a
//!                      provider *is*, not something the module links.
//!                      Default off; a linked build is unchanged.
//!   -Dtarget=<triple>  build for one target; `zig build check` then checks
//!                      that target only instead of the whole matrix.
//!
//! ## What is deliberately absent
//!
//! There is no `b.systemIntegrationOption`. `-fsys=cjson` would have to bind to
//! an installed libcjson *and* translate that installation's own headers, and
//! this host has no installed cJSON to compare against: bundling this release's
//! `src/cJSON.h` against an older installed library would compile and then
//! disagree at run time about the struct layout and the numeric ABI. The rule is
//! therefore recorded as withheld, not satisfied -- see UPSTREAM.md,
//! "System-library mode", and `WISDOM.md` W14.
//!
//! There is also no generated input. cJSON has no configure step, no table and
//! no per-target header, so nothing in this build is generated except the
//! runtime dispatch under `-Druntime`, and that is generated from the
//! translation step's real output for the target being built.

const std = @import("std");

/// The runtime-loading half, owned by the API role: the dispatch builder, and
/// the loader-core module a linked build imports for its two public types.
const runtime_graph = @import("runtime/graph.zig");

/// `build.zig.zon` itself. `@import` of the manifest is how a build script
/// reads `.version` without keeping a second copy of it.
const manifest = @import("build.zig.zon");

/// The artifact name. It is also the package name and the public module name,
/// so `zig-out/lib/libcjson.a`, `@import("cjson")` and `#include
/// <cjson/cJSON.h>` all name the same thing from three sides, and `zig build`'s
/// `-lcjson` is the name a C consumer's link line needs.
const artifact_name = "cjson";

/// The upstream public headers, relative to the vendored release tree.
const upstream_include = "src";

/// The one header `zig translate-c` runs over. It is not an upstream file: it
/// names the upstream header and includes it whole. See the file's own comment.
const translate_header = "zig/translate.h";

pub const facade_root = "zig/root.zig";
pub const tests_root = "tests.zig";
pub const smoke_root = "smoke.zig";

/// Where the behavioural tests find the fixture corpus on disk. Read at run
/// time rather than embedded: the corpus is 650 KB of JSON, most of it one
/// upstream example document, and embedding it would put those bytes in the
/// test object once per optimize mode and once per cross target.
pub const fixture_data_dir = "testdata";

/// The module name the test root imports to find that corpus. It has one
/// declaration, `pub const data_dir: []const u8`.
pub const fixture_module_name = "cjson_paths";

/// Upstream's version, read out of `src/cJSON.h:82-84`
/// (`CJSON_VERSION_MAJOR 1`, `CJSON_VERSION_MINOR 7`, `CJSON_VERSION_PATCH 19`)
/// and out of `src/CMakeLists.txt:5` (`VERSION 1.7.19`).
///
/// `src/cJSON.c:120-122` makes the header the authority at compile time: the
/// version function refuses to build unless these three macros are 1, 7 and 19.
/// `build` below compares this value against `build.zig.zon .version` and
/// refuses to configure when they disagree, so the manifest, the pkg-config
/// record and the compiled header cannot describe three different releases.
pub const upstream_version: std.SemanticVersion = .{ .major = 1, .minor = 7, .patch = 19 };

/// The shared object's version, and therefore its soname `libcjson.so.1`.
///
/// This is upstream's own number, not a fork-invented one: `src/CMakeLists.txt:12`
/// reads `set(CJSON_VERSION_SO 1)` and `:166-170` applies it as `SOVERSION` with
/// `VERSION "${PROJECT_VERSION}"`. `std.SemanticVersion` has three components
/// where an ELF shared object name has four, so the file is
/// `libcjson.so.1.7.19` and the soname is `libcjson.so.1`.
pub const abi_version: std.SemanticVersion = .{ .major = 1, .minor = 7, .patch = 19 };

/// The compiled core: upstream's complete library source list.
///
/// `src/CMakeLists.txt:101` and `:117`. `src/cJSON_Utils.c` is deliberately
/// absent and the reason is upstream's, not this fork's: upstream builds it as
/// a different target with its own soname (`src/CMakeLists.txt:13`,
/// `:213-221`). Shipping both in one archive would publish a `cJSONUtils_*`
/// surface under the `libcjson` name that upstream never gives it.
pub const library_sources = [_][]const u8{"src/cJSON.c"};

/// The public header upstream installs, and the directory it installs it into.
///
/// `src/CMakeLists.txt` installs the headers into `${CMAKE_INSTALL_FULL_INCLUDEDIR}/cjson`,
/// so a C consumer of an upstream install writes `#include <cjson/cJSON.h>`, and
/// this package installs to the same place rather than inventing a second
/// spelling of the same header.
pub const public_header = "src/cJSON.h";
pub const public_header_install_dir = "cjson";
pub const public_header_install_name = "cJSON.h";

/// Flags that describe the build, not the platform.
///
///   * `-DENABLE_LOCALES` -- upstream's default is ON (`src/CMakeLists.txt:273-276`),
///     so this package keeps it rather than silently taking the cheaper path.
///     What it turns on is `get_decimal_point()`, which asks `localeconv()` for
///     the decimal separator (`src/cJSON.c:279-287`); parsing substitutes it
///     before `strtod` (`src/cJSON.c:366-376`) and printing replaces it back
///     with `.` (`src/cJSON.c:641-652`). The JSON on the wire is the same in any
///     locale, and the observable consequence of the flag is that `localeconv()`
///     is in the parse and print path at all.
///   * `-fvisibility=hidden -DCJSON_API_VISIBILITY -DCJSON_EXPORT_SYMBOLS` --
///     exactly what upstream's own default configuration adds.
///     `src/CMakeLists.txt:86-90` is
///
///         option(ENABLE_PUBLIC_SYMBOLS "Export library symbols." On)
///         if (ENABLE_PUBLIC_SYMBOLS)
///             list(APPEND custom_compiler_flags -fvisibility=hidden)
///             add_definitions(-DCJSON_EXPORT_SYMBOLS -DCJSON_API_VISIBILITY)
///         endif()
///
///     and `ENABLE_HIDDEN_SYMBOLS`, the branch that would replace them, is off
///     (`src/CMakeLists.txt:91-94`). Together they make `CJSON_PUBLIC` the only
///     thing with default visibility (`src/cJSON.h:74-78`) or with `dllexport`
///     (`src/cJSON.h:63-69`), which is the export surface of the artifact. This
///     is the header's own documented mechanism (`src/cJSON.h:37-53`), used the
///     way upstream uses it.
///
/// The export surface is therefore decided at compile time, not at link time,
/// and this build adds no version script and no generated module definition for
/// it. fast_float needs a linker arm for the opposite reason -- its bridge
/// header declares nothing (`fast_float/build_support/graph.zig:36-52`) -- so
/// adding one here would be a second list to keep in step with a header that
/// already carries the answer.
///
/// No `-std=` appears here and the omission is deliberate: upstream sets no
/// `C_STANDARD` and no `-std` (`src/CMakeLists.txt`, `src/Makefile:34-40`), and
/// the source is written to the older dialect on purpose. Pinning a dialect
/// here would be a second answer to a question upstream leaves to the compiler,
/// and a newer dialect could admit constructs that change which branch of the
/// code compiles.
const library_flags = [_][]const u8{
    "-DENABLE_LOCALES",
    "-fvisibility=hidden",
    "-DCJSON_API_VISIBILITY",
    "-DCJSON_EXPORT_SYMBOLS",
};

/// The cross-target compile matrix. Every entry must compile the C core, the
/// translated header, the facade, the behavioural tests and the smoke example.
/// Nothing here is skipped and nothing is pre-judged: if a target cannot be
/// built, the compile is attempted and reports why.
pub const required_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Whether the caller named a target on the command line.
///
/// `standardTargetOptions` cannot answer this: it folds `-Dtarget=X` and "no
/// -Dtarget at all" into the same resolved value. The raw option table can,
/// because `standardTargetOptionsQueryOnly` registers the option by exactly that
/// name and every `-Dname=value` the user passed is a key in it.
fn target_was_named(b: *const std.Build) bool {
    return b.user_input_options.contains("target");
}

/// Whether this target can carry a shared object at all.
///
/// For most targets that is exactly the question `std.Target.DynamicLinker.kind`
/// answers from the OS tag alone. Windows is the one exception: a PE/COFF image
/// has no interpreter path, because its imports are resolved by the loader
/// inside the OS, yet a Windows target carries a shared object perfectly well,
/// as `cjson.dll` plus its import library.
pub fn targetCarriesSharedObject(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag == .windows) return true;
    return std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Why a requested shared object cannot be delivered for one target, or `null`
/// when it can.
///
/// A refusal, not a substitution. There is no third answer: this build either
/// delivers the artifact the caller named or it fails saying which target
/// refused it and why.
pub fn sharedObjectRefusal(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) ?[]const u8 {
    if (targetCarriesSharedObject(target)) return null;
    return b.fmt(
        "-Dlinkage=dynamic was requested and {s} cannot carry a shared object: " ++
            "its OS has no dynamic linker, so a shared library there is a file " ++
            "nothing can load. Nothing was substituted. Build this target with " ++
            "-Dlinkage=static, which is the default, or name a target whose " ++
            "platform has a loader.",
        .{@tagName(target.result.os.tag)},
    );
}

/// One target's compiled artifacts.
pub const Graph = struct {
    /// The native library a C consumer links. It is built and installed in both
    /// configurations: under `-Druntime` it is what a provider *is*, not
    /// something the module links.
    library: *std.Build.Step.Compile,
    /// The Zig facade. Its `c` import is the translated header in a linked build
    /// and the generated runtime dispatch in a runtime-loading one.
    module: *std.Build.Module,
};

/// Builds the native core, translates the public header, and builds the facade
/// module over both.
///
/// `name` is the artifact name this graph reports: the package name for the
/// published graph, and a target-decorated name for a cross-target check, since
/// six graphs in one build would otherwise produce six steps called `cjson`.
///
/// `public` selects between the package module set -- what a dependent reaches
/// through `dep.module("cjson")` -- and a private module. A cross-target check
/// needs the private form: modules are registered by name against the whole
/// build, so registering `cjson` once per cross target would leave only the last
/// of them reachable and silently stop checking the rest.
///
/// ## The runtime-loading seam
///
/// `runtime/graph.zig` exposes `createModule`, and `-Druntime` substitutes that
/// one call for the translated module. It is handed the very `translate_c` step
/// built below, so the generated dispatch keeps the exact translated constant
/// namespace rather than compiling a second copy of it: `c.cJSON_VERSION_MAJOR`
/// in a facade and the declaration behind the table are one value with one
/// spelling.
///
/// Two things are deliberately *not* done in that branch: the archive is not
/// linked into the module (linking it would make the linker resolve the same
/// symbols statically and the runtime route would quietly be a linked one), and
/// the loader core module is not created a second time, because `createModule`
/// makes the one instance the dispatch re-exports `LoadSource`/`LoadError` from.
pub fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    name: []const u8,
    public: bool,
    runtime_loaded: bool,
) Graph {
    const library_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // `<stdlib.h>`, `<string.h>`, `<math.h>`, `<limits.h>`, `<ctype.h>` and
        // `<float.h>` all arrive through `src/cJSON.c:40-46`.
        .link_libc = true,
        // A shared object has to be position independent or the loader cannot
        // place it away from its link address. `null` is the compiler's own
        // choice, which is what the static delivery builds.
        .pic = if (linkage == .dynamic) true else null,
    });
    // The vendored headers have to be on the library's own compile line, not
    // only on the include tree this build installs.
    library_mod.addIncludePath(b.path(upstream_include));
    library_mod.addCSourceFiles(.{
        .files = &library_sources,
        .flags = &library_flags,
        .language = .c,
    });

    const library = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        // `null` for the static archive, which has no soname and no versioned
        // file name; upstream's own numbers for the shared object.
        .version = if (linkage == .dynamic) abi_version else null,
        // No generated module definition: `src/cJSON.h:66` already spells
        // `__declspec(dllexport)` through `CJSON_EXPORT_SYMBOLS` on Windows, so
        // a `.def` file here would be a second export list to keep in step.
        .root_module = library_mod,
    });

    // The public header goes in beside the library, under the directory
    // upstream installs it into. Attaching it to the artifact also puts it on
    // the include search path of anything that links it.
    library.installHeader(
        b.path(public_header),
        b.fmt("{s}/{s}", .{ public_header_install_dir, public_header_install_name }),
    );

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path(translate_header),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // The translation has to see the same header the library was compiled
    // against, under the same configuration macros, or the translated
    // declarations would describe a different build of the same header.
    translate_c.addIncludePath(b.path(upstream_include));
    translate_c.defineCMacro("ENABLE_LOCALES", null);
    translate_c.defineCMacro("CJSON_API_VISIBILITY", null);
    if (target.result.os.tag == .windows) {
        translate_c.defineCMacro("CJSON_EXPORT_SYMBOLS", null);
    }

    const c_module = if (runtime_loaded)
        runtime_graph.createModule(b, translate_c, target, optimize)
    else if (public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    const module = if (public)
        b.addModule(artifact_name, .{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path(facade_root),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    module.addImport("c", c_module);
    if (!runtime_loaded) {
        // `rt` carries the two public types a linked build has no dispatch for.
        // A runtime-loading build must not add it: the dispatch re-exports both
        // from the one core instance `createModule` made.
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));
        module.linkLibrary(library);
    }

    return .{ .library = library, .module = module };
}

/// Installs `lib/pkgconfig/cjson.pc`.
///
/// `prefix` is `${pcfiledir}/../..`, not the `--prefix` this build was
/// configured with. pkg-config substitutes `pcfiledir` with the directory it
/// found the file in, so the installed record is right for the prefix actually
/// installed under, including a `--prefix` chosen after configuration or a tree
/// moved after installation.
///
/// `Cflags` carries `CJSON_IMPORT_SYMBOLS` only for the shared delivery, and the
/// reason is in the header: `src/cJSON.h:67` turns `CJSON_PUBLIC` into
/// `__declspec(dllimport)` under that macro, which is what a consumer of a DLL
/// wants. The archive needs nothing -- upstream's own default for a static build
/// is `CJSON_EXPORT_SYMBOLS` (`src/cJSON.h:59-61`), and putting a flag in
/// `Cflags` that is false for the installed artifact is how a pkg-config record
/// starts lying.
///
/// `Libs.private` is empty for both deliveries. The compiled closure is one C
/// file whose only library dependencies are `malloc`, `free`, `realloc`,
/// `memcpy`, `strlen` and `strtod`, all of which are libc, and libc is linked by
/// every consumer of a C library without being told. There is no `-lm`: `math.h`
/// is included (`src/cJSON.c:43`) but the only names used from it are `isnan` and
/// `isinf`, which `src/cJSON.c:72-78` defines as expressions rather than calls.
pub fn addPkgConfig(b: *std.Build, linkage: std.builtin.LinkMode) void {
    const import_flag = if (linkage == .dynamic) " -DCJSON_IMPORT_SYMBOLS" else "";
    const pc = b.addWriteFiles().add("cjson.pc", b.fmt(
        \\# Generated by this package's build.zig from its own install layout.
        \\# Do not edit; see build.zig, addPkgConfig.
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: cJSON
        \\Description: cJSON, an ultra-lightweight JSON parser in ANSI C, packaged for Zig 0.16
        \\URL: https://github.com/DaveGamble/cJSON
        \\Version: {f}
        \\
        \\Libs: -L"${{libdir}}" -lcjson
        \\Cflags: -I"${{includedir}}"{s}
        \\
    , .{ upstream_version, import_flag }));
    const install_pc = b.addInstallFileWithDir(pc, .lib, "pkgconfig/cjson.pc");
    b.getInstallStep().dependOn(&install_pc.step);
}

/// One carried licence or provenance record, and the name it is installed under.
pub const LicenceRecord = struct {
    source: []const u8,
    installed_name: []const u8,
};

/// The licence and provenance material an installed binary form has to carry.
///
/// `src/LICENSE` is cJSON's own MIT text and it is the licence of every
/// compiled line; it is installed under a distinct name because a consumer
/// looking for the package's own terms has to be able to tell it from
/// `FORK-LICENSE.md`, which covers only this fork's additions.
pub const licence_records = [_]LicenceRecord{
    .{ .source = "src/LICENSE", .installed_name = "LICENSE.cJSON" },
    .{ .source = "NOTICE.md", .installed_name = "NOTICE.md" },
    .{ .source = "FORK-LICENSE.md", .installed_name = "FORK-LICENSE.md" },
    .{ .source = "UPSTREAM.md", .installed_name = "UPSTREAM.md" },
    .{ .source = "README.upstream.md", .installed_name = "README.upstream.md" },
};

/// Installs the carried licence texts and provenance records under
/// `share/licenses/cjson/`.
///
/// The install steps use `b.installFile`, which attaches them to the install
/// step; `b.addInstallFileWithDir` merely creates an `InstallFile` step and
/// returns it without attaching it, and an unattached step is never made, so the
/// record would be absent from every prefix while `zig build` still exited zero.
pub fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(
            record.source,
            b.fmt("share/licenses/{s}/{s}", .{ artifact_name, record.installed_name }),
        );
    }
}

/// Where the behavioural tests find the fixture corpus on disk.
///
/// This is a build option module rather than an `@embedFile` and rather than a
/// convention, so the test root never guesses. `addOptionPath` resolves its
/// `LazyPath` inside the options step's make phase, which is where a path built
/// during `build()` is allowed to resolve, and renders it relative to the build
/// root. That relative path is sound at run time because a run step with no
/// explicit working directory inherits the build runner's, and `zig build` only
/// runs from the directory holding `build.zig` -- which is also what an external
/// executor (QEMU user mode, Wine, wasmtime) inherits.
pub fn addFixturePaths(b: *std.Build) *std.Build.Module {
    const options = b.addOptions();
    options.addOptionPath("data_dir", b.path(fixture_data_dir));
    return options.createModule();
}

/// The behavioural test binary for one graph.
///
/// The facade is reachable only through this binary on the cross-target path,
/// which is what makes the check a check of the facade: Zig analyses a function
/// body when something calls it, every public facade method is called from
/// `tests.zig`, and building this binary for a target analyses all of them.
///
/// It is the same artifact either way: `check` compiles it and stops there,
/// `test` compiles it and hands it to a run step. There is no reduced test root
/// for the foreign path, so a target that runs these tests runs the whole
/// corpus, at both widths, as the host does.
pub fn addTests(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    fixtures: *std.Build.Module,
) *std.Build.Step.Compile {
    const test_mod = b.createModule(.{
        .root_source_file = b.path(tests_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(artifact_name, graph.module);
    test_mod.addImport(fixture_module_name, fixtures);
    return b.addTest(.{ .name = name, .root_module = test_mod });
}

/// The smoke example for one graph. Compiling it, and running it where the
/// target can run, is the cheapest end-to-end proof that the facade, the
/// translated header and the compiled core agree on types and symbols.
pub fn addSmoke(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
) *std.Build.Step.Compile {
    const smoke_mod = b.createModule(.{
        .root_source_file = b.path(smoke_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addImport(artifact_name, graph.module);
    return b.addExecutable(.{ .name = name, .root_module = smoke_mod });
}

/// Compiles the core, the translated header, the facade, the tests and the
/// example for one target, and attaches both binaries to `parent`.
///
/// Nothing is run. A cross-built binary cannot be executed on the host, so this
/// is compile evidence and never a claim that a foreign binary executed.
///
/// A cell that cannot deliver what the caller asked for becomes a failing step
/// carrying the reason, and nothing is compiled for it. That is the honest
/// result of `zig build check -Dlinkage=dynamic` for `wasm32-wasi`: an explicit
/// refusal for that one cell, with the other five still compiled.
pub fn addTargetCheck(
    b: *std.Build,
    parent: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    fixtures: *std.Build.Module,
) void {
    const target = b.resolveTargetQuery(query);
    // Artifact names have to stay unique inside one build graph.
    const label = b.fmt("{s}-{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag) });

    if (linkage == .dynamic) {
        if (sharedObjectRefusal(b, target)) |reason| {
            parent.dependOn(&b.addFail(b.fmt(
                "{s}: {s} No artifact was built for this cell.",
                .{ label, reason },
            )).step);
            return;
        }
    }

    const graph = addGraph(
        b,
        target,
        optimize,
        linkage,
        b.fmt("{s}-{s}", .{ artifact_name, label }),
        false,
        runtime_loaded,
    );

    parent.dependOn(
        &addTests(b, graph, target, optimize, b.fmt("{s}-tests-{s}", .{ artifact_name, label }), fixtures).step,
    );
    parent.dependOn(
        &addSmoke(b, graph, target, optimize, b.fmt("{s}-smoke-{s}", .{ artifact_name, label })).step,
    );
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // `build.zig.zon .version`, the version read out of upstream's own header
    // and CMakeLists, and the version the installed `cjson.pc` states are one
    // fact. The comparison catches a manifest edited without the source it
    // describes rather than letting three documents name three releases.
    const manifest_version = std.SemanticVersion.parse(manifest.version) catch
        @panic("build.zig.zon: .version is not a semantic version");
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of src/cJSON.h:82-84 and src/CMakeLists.txt:5; see UPSTREAM.md");
    }

    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver libcjson as a static archive (the default) or as a shared " ++
            "object carrying upstream's own SOVERSION. Both variants compile " ++
            "the same upstream source with the same macros; the option selects " ++
            "the delivery and never the dispatch. A target whose OS has no " ++
            "dynamic linker -- wasm32-wasi, which this package's own matrix " ++
            "walks -- cannot deliver a shared object, and asking for one there " ++
            "fails rather than falling back to an archive.",
    ) orelse .static;

    // A requested artifact this target cannot carry is refused, never replaced.
    // The check is here, once, before any graph is built, and `addTargetCheck`
    // applies the same refusal per matrix cell, so the two paths cannot disagree
    // about which targets can carry one.
    if (linkage == .dynamic) {
        if (sharedObjectRefusal(b, target)) |reason| @panic(reason);
    }

    // `-Druntime` selects the *dispatch*, and it is orthogonal to `-Dlinkage`:
    // that option says which artifact this build delivers and installs, this one
    // says whether the facade calls it through a link line or through a table an
    // explicit `load(source)` fills.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the library's entry points at run time instead of linking " ++
            "them. The facade keeps the same translated header and the same " ++
            "public types; each selected native function becomes a dispatch " ++
            "through one process-lifetime table that an explicit load(source) " ++
            "fills, and the module links no archive. Independent of -Dlinkage, " ++
            "which still decides the artifact this build delivers and installs. " ++
            "Default off, and a linked build is unchanged in every respect.",
    ) orelse false;

    const native = addGraph(b, target, optimize, linkage, artifact_name, true, runtime_loaded);

    // Built once and shared: the corpus directory is the same for the test run
    // of whichever target was selected, for the six cross-target compiles of the
    // same test root, and for every target of an external matrix driver.
    const fixtures = addFixturePaths(b);

    // `zig build` installs the whole closure, not just the archive: a C consumer
    // gets `#include <cjson/cJSON.h>` and `-lcjson` without reaching into this
    // repository; a consumer handed the prefix gets an answer from pkg-config;
    // and the binary travels with the licence material that covers it, which a
    // private repository does not remove.
    b.installArtifact(native.library);
    addPkgConfig(b, linkage);
    installLicenceRecords(b);

    const smoke_exe = addSmoke(b, native, target, optimize, "cjson-smoke");
    // Compiled but not run by the default step: installing is `zig build`'s job,
    // and a default step that executes a program is a side effect nobody asked
    // for. `zig build smoke` runs it.
    b.getInstallStep().dependOn(&smoke_exe.step);

    const run_smoke = b.addRunArtifact(smoke_exe);
    // Without this flag a run step whose inputs did not change is served from
    // the cache and the program never runs, which would let a second
    // `zig build smoke` report success without observing anything.
    run_smoke.has_side_effects = true;
    b.step("smoke", "Run the smoke example and check its answers").dependOn(&run_smoke.step);

    const tests = addTests(b, native, target, optimize, "cjson-tests", fixtures);
    const test_step = b.step("test", "Run the cJSON behavioural tests for the selected target");

    // Unconditional, for every target the caller selected, the host included.
    // A host target executes; a foreign target executes through whatever
    // external executor the driver supplies; a foreign target with no executor
    // is skipped with its compile dependencies intact, which is build-only
    // coverage and never a pass. Deciding that policy belongs to the driver
    // that owns the step.
    const run_tests = b.addRunArtifact(tests);
    // A test run whose compile step is unchanged is otherwise served from the
    // run cache and never executes: for a binary whose tests read their fixture
    // corpus off disk that would report a pass without reading anything, because
    // those files are not inputs to the run step's hash.
    run_tests.has_side_effects = true;
    test_step.dependOn(&run_tests.step);

    const check_step = b.step(
        "check",
        "Compile the native core, the translated header, the facade, the tests and the example for all six required targets without running them",
    );
    if (target_was_named(b)) {
        addTargetCheck(b, check_step, target.query, optimize, linkage, runtime_loaded, fixtures);
    } else {
        for (required_targets) |query| {
            addTargetCheck(b, check_step, query, optimize, linkage, runtime_loaded, fixtures);
        }
    }

    // Which artifact this configuration hands back is a fact worth reading out
    // of the build rather than inferring from a cache directory. These are
    // configure-time lines, not gate results: nothing has been compiled when
    // they print.
    std.debug.print("cjson: upstream {f}, {s}\n", .{
        upstream_version,
        switch (linkage) {
            .static => "static archive, libcjson.a (default)",
            .dynamic => b.fmt("shared object, soname lib{s}.so.{d}", .{
                artifact_name,
                abi_version.major,
            }),
        },
    });
    if (runtime_loaded) {
        // Dispatch is a separate fact from delivery: a runtime-loaded build
        // links nothing into the module, and a provider is named by an explicit
        // `load(source)`. The artifact above is still built and installed; it is
        // what a `.path` or `.system` load may name.
        std.debug.print(
            "cjson: runtime-loaded dispatch (-Druntime=true); no library is linked " ++
                "into the module, and a provider is named by an explicit " ++
                "load(source). The artifact above is still built and installed; it " ++
                "is what a .path or .system load may name.\n",
            .{},
        );
        if (linkage == .static) {
            // A fact about this combination, not a correction of it: the two
            // options are orthogonal and this one is legal. An archive cannot be
            // opened by a loader, so the provider a caller names has to be a
            // shared object -- the one `-Dlinkage=dynamic` installs, or one this
            // tree never built.
            std.debug.print(
                "cjson: -Dlinkage=static with -Druntime: the installed artifact is " ++
                    "an archive, which a loader cannot open. A provider has to be " ++
                    "a shared object -- the one -Dlinkage=dynamic installs, or one " ++
                    "named by the caller.\n",
                .{},
            );
        }
    }
}