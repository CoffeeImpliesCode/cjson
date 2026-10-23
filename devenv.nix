# Canonical development environment for cJSON.
# SPDX-License-Identifier: MIT

{ pkgs, ... }:

let
  # Pin the compiler used by tasks and package derivations.
  zig = pkgs.zig_0_16;

  cjson = linkage: pkgs.callPackage ./package.nix {
    inherit linkage;
    zig = zig;
  };

  # Use this checkout path without adding it to the Nix store context.
  sdk_root = builtins.toString ./.;

  # Default Zig caches outside the checkout; preserve caller-supplied paths.
  zig_caches = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$XDG_CACHE_HOME/cjson/zig-local-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$TMPDIR/cjson/zig-local-cache"
      fi
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$XDG_CACHE_HOME/cjson/zig-global-cache"
      elif [ -n "''${TMPDIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/cjson/zig-global-cache"
      fi
    fi
    if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_LOCAL_CACHE_DIR"
    fi
    if [ -n "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
  '';

  # Tasks require an external writable cache directory.
  require_external_output = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      echo "cjson devenv: ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME and TMPDIR are all unset," >&2
      echo "so there is nowhere outside this checkout to put build output." >&2
      echo "Export one of them at approved scratch, then run the task again." >&2
      exit 1
    fi
  '';

  # Each generated task must enter this checkout before running.
  in_sdk = ''
    ${zig_caches}
    ${require_external_output}
    cd "${sdk_root}" || exit 1
  '';

  # Shared native-build flags; caller arguments come last.
  native_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/native" "''$@"
  '';

  # Keep the consumer build in a separate cache.
  consumer_flags = ''
    -j8 --summary all --cache-dir "$ZIG_LOCAL_CACHE_DIR/consumer" "''$@"
  '';
in
{
  packages = [
    zig
    pkgs.gnumake
    pkgs.pkg-config
    pkgs.valgrind
  ];

  assertions = [
    {
      assertion = zig.version == "0.16.0";
      message = "The cJSON SDK requires Zig 0.16.0; nixpkgs resolved zig_0_16 to ${zig.version}";
    }
  ];

  # Apply the external cache defaults in an interactive shell.
  enterShell = ''
    ${zig_caches}
  '';

  # Outputs are lazy derivations; they build only when requested.
  outputs.static = cjson "static";
  outputs.shared = cjson "dynamic";
  outputs.default = cjson "static";

  tasks = {
    # Install outside the checkout.
    "sdk:build" = {
      description = ''
        Compile the native library (default step) and install the delivery tree
        under the external cache rather than in this checkout.
      '';
      exec = ''
        ${in_sdk}
        zig build --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/static" ${native_flags}
      '';
    };

    "sdk:build:shared" = {
      description = ''
        Compile the native library as a shared object instead of an archive, and
        install it under its own external prefix.
      '';
      exec = ''
        ${in_sdk}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${native_flags}
      '';
    };

    "sdk:test" = {
      description = "Run the behavioural tests";
      exec = ''
        ${in_sdk}
        zig build test ${native_flags}
      '';
    };

    "sdk:test:release-safe" = {
      description = "Run the behavioural tests in ReleaseSafe";
      exec = ''
        ${in_sdk}
        zig build test -Doptimize=ReleaseSafe ${native_flags}
      '';
    };

    "sdk:smoke" = {
      description = "Run the deterministic example";
      exec = ''
        ${in_sdk}
        zig build smoke ${native_flags}
      '';
    };

    "sdk:check" = {
      description = "Compile and link the library, the facade, the tests and the example for all six required targets, without running any of them";
      exec = ''
        ${in_sdk}
        zig build check ${native_flags}
      '';
    };

    "sdk:check:shared" = {
      description = ''
        The same six-target compile check against the shared object. wasm32-wasi
        is refused for this linkage with a message naming it, because its OS has
        no dynamic linker; the other five still compile.
      '';
      exec = ''
        ${in_sdk}
        zig build check -Dlinkage=dynamic ${native_flags}
      '';
    };

    # Build the separate dependent package through its path dependency.
    "sdk:consumer" = {
      description = "Build and run the separate consumer package against this SDK";
      exec = ''
        ${in_sdk}
        cd consumer
        zig build run ${consumer_flags}
      '';
    };

    # Build the shared provider before testing runtime loading.
    "sdk:test:loaded" = {
      description = ''
        Build the runtime-loaded configuration, install the shared object it
        dispatches to, and run the behavioural tests against that provider.
      '';
      exec = ''
        ${in_sdk}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${native_flags}
        CJSON_PROVIDER="$ZIG_LOCAL_CACHE_DIR/prefix/dynamic/lib/libcjson.so" \
          zig build test -Druntime=true ${native_flags}
      '';
    };

    "sdk:consumer:loaded" = {
      description = ''
        Run the consumer package against the runtime-loaded configuration, with
        the provider named on its command line.
      '';
      exec = ''
        ${in_sdk}
        zig build -Dlinkage=dynamic --prefix "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic" ${native_flags}
        cd consumer
        zig build run -Druntime=true ${consumer_flags} -- \
          --provider "$ZIG_LOCAL_CACHE_DIR/prefix/dynamic/lib/libcjson.so"
      '';
    };

    # Run provenance checks from this checkout.
    "sdk:provenance" = {
      description = ''
        Check the 238 recorded digests, the exact file set, the preserved upstream
        README bytes, cJSON's own notice, the vendored Unity and JSON Patch
        notices, the compiled source list and the version triple. This is a
        source-integrity check, not a build gate.
      '';
      exec = ''
        ${in_sdk}
        bash tools/check-provenance.sh
      '';
    };

    # Package tasks run in the caller's project, not this checkout.
    "sdk:package:static" = {
      description = ''
        Build the static Nix variant through devenv's own lazy output. No lock
        is needed by this path; `devenv build outputs.static` resolves the
        pinned input from devenv.lock, which the driver owns.
      '';
      exec = "devenv build outputs.static";
    };

    "sdk:package:shared" = {
      description = "Build the shared Nix variant through devenv's own lazy output";
      exec = "devenv build outputs.shared";
    };
  };
}