# Source-only cJSON package derivation.
#
# SPDX-License-Identifier: MIT

{ lib
, stdenv
, zig
, patchelf
  # Empty leaves build.zig's default; otherwise select static or dynamic.
, linkage ? "static"
, optimize ? "ReleaseSafe"
}:

let
  requestedLinkage =
    if builtins.elem linkage [ "" "static" "dynamic" ] then linkage
    else throw "package.nix: linkage must be \"\", \"static\" or \"dynamic\", not ${toString linkage}";

  # Exclude VCS and build-tool state from the packaged source.
src = lib.cleanSourceWith {
  src = ./.;
  filter = path: _type:
    let name = builtins.baseNameOf (toString path); in
    !(lib.elem name [
      ".git"
      ".direnv"
      ".devenv"
      ".zig-cache"
      "zig-cache"
      "zig-pkg"
      "zig-out"
      "result"
    ]);
};

  # patchelf is used only for ELF targets.
isElfTarget = !stdenv.hostPlatform.isDarwin;
in

  # Restrict this derivation to the compiler's native target.
assert stdenv.buildPlatform.system == stdenv.hostPlatform.system;

stdenv.mkDerivation {
  pname = "cjson";
  version = "1.7.19";

  inherit src;

  strictDeps = true;
  dontPatch = true;

  # Skip the Zig hook's implicit configure/build; installPhase runs the explicit build.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ zig ] ++ lib.optional isElfTarget patchelf;

  # cJSON's only external link dependency is libc (src/cJSON.c:40-46).
  propagatedBuildInputs = [ stdenv.cc.libc ];


  doCheck = false;
  dontUseZigCheck = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches outside the unpacked source tree.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    # build.zig owns the compiled sources, flags, pkg-config record, and install paths.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=${optimize} \
      -Dcpu=baseline \
      ${lib.optionalString (requestedLinkage != "") "-Dlinkage=${requestedLinkage}"}

    # Remove TMPDIR entries from ELF rpaths and retain runtime dependency paths.
    # Resolve soname symlinks before rewriting the rpath.
    ${lib.optionalString isElfTarget ''
      for elf in "$out"/bin/* "$out"/lib/*.so*; do
        [ -f "$elf" ] || continue
        elf=$(readlink -f "$elf")
        rpath=$(patchelf --print-rpath "$elf") || rpath=""
        kept=""
        rest=$rpath
        while [ -n "$rest" ]; do
          entry="''${rest%%:*}"
          case "$entry" in
            "$TMPDIR"/*) ;;
            *) if [ -z "$kept" ]; then kept=$entry; else kept=$kept:$entry; fi ;;
          esac
          if [ "$entry" = "$rest" ]; then rest=""; else rest="''${rest#*:}"; fi
        done
        [ "$kept" = "$rpath" ] || patchelf --set-rpath "$kept" "$elf"
      done
    ''}

    runHook postInstall
  '';



  enableParallelBuilding = true;

  meta = {
    description = "cJSON 1.7.19, an ultra-lightweight JSON parser in ANSI C, built from the official release sources";
    longDescription = ''
      The complete cJSON 1.7.19 release source -- the library, its public
      headers, the companion cJSON_Utils pair, the full upstream test suite with
      the Unity framework it vendors, the JSON Patch corpus it vendors, the
      fuzzing harnesses and upstream's own build files -- imported whole and
      compiled with Zig, with no CMake, no make and no build-time download. Ships
      the library, the public header, a pkg-config file and both licence grants.
      The compiled core is upstream's own library source list, one file.
    '';
    # NOTICE.md maps the MIT and Apache-2.0 materials in the shipped tree.
    license = with lib.licenses; { mit = true; apache2 = true; };
    platforms = lib.platforms.unix;
  };
}