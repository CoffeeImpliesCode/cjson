// SPDX-License-Identifier: MIT
// License scope: FORK-LICENSE.md and NOTICE.md.
//! Build graph for the cJSON Zig package.

const std = @import("std");

const runtime_graph = @import("runtime/graph.zig");

const manifest = @import("build.zig.zon");

/// Shared package, module, and artifact name.
const artifact_name = "cjson";

const upstream_include = "src";
const translate_header = "zig/translate.h";

pub const facade_root = "zig/root.zig";
pub const tests_root = "tests.zig";
pub const smoke_root = "smoke.zig";

/// Fixture directory read by tests at run time.
pub const fixture_data_dir = "testdata";

pub const fixture_module_name = "cjson_paths";

/// Upstream version; `build()` checks it against `build.zig.zon`.
pub const upstream_version: std.SemanticVersion = .{ .major = 1, .minor = 7, .patch = 19 };

/// Upstream shared-object ABI version.
pub const abi_version: std.SemanticVersion = .{ .major = 1, .minor = 7, .patch = 19 };

/// Upstream builds `cJSON_Utils.c` as a separate target (src/CMakeLists.txt:213-221).
pub const library_sources = [_][]const u8{"src/cJSON.c"};

pub const public_header = "src/cJSON.h";
pub const public_header_install_dir = "cjson";
pub const public_header_install_name = "cJSON.h";

// Match upstream's locale and public-symbol defaults (src/CMakeLists.txt:86-94,273-276).
const library_flags = [_][]const u8{
    "-DENABLE_LOCALES",
    "-fvisibility=hidden",
    "-DCJSON_API_VISIBILITY",
    "-DCJSON_EXPORT_SYMBOLS",
};

/// Targets compiled by the package's cross-target check.
pub const required_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// True when the caller passed `-Dtarget`; resolved defaults do not distinguish it.
fn target_was_named(b: *const std.Build) bool {
    return b.user_input_options.contains("target");
}

/// Whether the target can carry a shared object; Windows uses PE imports, not a dynamic linker.
pub fn targetCarriesSharedObject(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag == .windows) return true;
    return std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Returns why shared-object delivery is unavailable, or `null`.
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

/// One target's library and facade module.
pub const Graph = struct {
    /// The delivered library; runtime-loaded facades do not link it.
    library: *std.Build.Step.Compile,
    /// The public Zig facade.
    module: *std.Build.Module,
};

/// Builds the native library, translated header, and facade module for one target.
pub fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    name: []const u8,
    public: bool,
    runtime_loaded: bool,
) Graph {
    const library_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // Shared objects require position-independent code.
        .pic = if (linkage == .dynamic) true else null,
    });
    // Keep vendored headers on the library compile path.
    library_mod.addIncludePath(b.path(upstream_include));
    library_mod.addCSourceFiles(.{
        .files = &library_sources,
        .flags = &library_flags,
        .language = .c,
    });

    const library = b.addLibrary(.{
        .name = name,
        .linkage = linkage,
        .version = if (linkage == .dynamic) abi_version else null,
        // The header exports Windows symbols; a `.def` would duplicate the list (src/cJSON.h:63-69).
        .root_module = library_mod,
    });

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
    // Translate the same header with the library's include path and macros.
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
        // Runtime dispatch re-exports `rt`; linked builds import the core directly.
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));
        module.linkLibrary(library);
    }

    return .{ .library = library, .module = module };
}

/// Writes an install-relative pkg-config file for the selected linkage.
/// Shared Windows consumers receive `CJSON_IMPORT_SYMBOLS`; static consumers do not.
pub fn addPkgConfig(b: *std.Build, linkage: std.lang.LinkMode) void {
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
        \\Description: cJSON, an ultra-lightweight JSON parser in ANSI C, packaged for Zig 0.17.0
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

/// The licence and provenance records installed with the package.
pub const licence_records = [_]LicenceRecord{
    .{ .source = "src/LICENSE", .installed_name = "LICENSE.cJSON" },
    .{ .source = "NOTICE.md", .installed_name = "NOTICE.md" },
    .{ .source = "FORK-LICENSE.md", .installed_name = "FORK-LICENSE.md" },
    .{ .source = "UPSTREAM.md", .installed_name = "UPSTREAM.md" },
    .{ .source = "README.upstream.md", .installed_name = "README.upstream.md" },
};

/// Installs the package's licence and provenance records.
// `b.installFile` attaches each record to the install step.
pub fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(
            record.source,
            b.fmt("share/licenses/{s}/{s}", .{ artifact_name, record.installed_name }),
        );
    }
}

/// Adds the fixture directory as a build option for the test module.
pub fn addFixturePaths(b: *std.Build) *std.Build.Module {
    const options = b.addOptions();
    options.addOptionPathDirectory("data_dir", b.path(fixture_data_dir));
    return options.createModule();
}

/// Builds the behavioral test binary for one target.
pub fn addTests(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
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

/// Builds the smoke example for one target.
pub fn addSmoke(
    b: *std.Build,
    graph: Graph,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
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

/// Compiles tests and the smoke example for one target without running them.
pub fn addTargetCheck(
    b: *std.Build,
    parent: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.lang.Optimize,
    linkage: std.lang.LinkMode,
    runtime_loaded: bool,
    fixtures: *std.Build.Module,
) void {
    const target = b.resolveTargetQuery(query);
    // Target labels keep artifact names unique in one build graph.
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

    const manifest_version = std.SemanticVersion.parse(manifest.version) catch
        @panic("build.zig.zon: .version is not a semantic version");
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the version read out " ++
            "of src/cJSON.h:82-84 and src/CMakeLists.txt:5; see UPSTREAM.md");
    }

    const linkage = b.option(
        std.lang.LinkMode,
        "linkage",
        "Deliver libcjson as a static archive (the default) or as a shared " ++
            "object carrying upstream's own SOVERSION. Both variants compile " ++
            "the same upstream source with the same macros; the option selects " ++
            "the delivery and never the dispatch. A target whose OS has no " ++
            "dynamic linker -- wasm32-wasi, which this package's own matrix " ++
            "walks -- cannot deliver a shared object, and asking for one there " ++
            "fails rather than falling back to an archive.",
    ) orelse .static;

    if (linkage == .dynamic) {
        if (sharedObjectRefusal(b, target)) |reason| @panic(reason);
    }

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

    const fixtures = addFixturePaths(b);

    b.installArtifact(native.library);
    addPkgConfig(b, linkage);
    installLicenceRecords(b);

    const smoke_exe = addSmoke(b, native, target, optimize, "cjson-smoke");
    // The install step builds the smoke binary but does not run it.
    b.getInstallStep().dependOn(&smoke_exe.step);

    const run_smoke = b.addRunArtifact(smoke_exe);
    // Force execution; Zig otherwise reuses cached run-step results.
    run_smoke.has_side_effects = true;
    b.step("smoke", "Run the smoke example and check its answers").dependOn(&run_smoke.step);

    const tests = addTests(b, native, target, optimize, "cjson-tests", fixtures);
    const test_step = b.step("test", "Run the cJSON behavioural tests for the selected target");

    const run_tests = b.addRunArtifact(tests);
    // Fixture files are outside the run-step hash, so force each test run.
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
        std.debug.print(
            "cjson: runtime-loaded dispatch (-Druntime=true); no library is linked " ++
                "into the module, and a provider is named by an explicit " ++
                "load(source). The artifact above is still built and installed; it " ++
                "is what a .path or .system load may name.\n",
            .{},
        );
        if (linkage == .static) {
            // Runtime providers must be shared objects, even when this build installs an archive.
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
