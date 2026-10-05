#!/usr/bin/env bash
# Source-integrity check for the cJSON SDK.
#
# Five questions, all answerable without a compiler:
#
#   1. Do the 238 recorded files still hash to the digests UPSTREAM.sha256 says?
#   2. Is the native file set exactly that set -- no missing, extra or renamed
#      file under `src/` or `testdata/`?  A plain checksum run cannot see an
#      addition.
#   3. Is the preserved upstream README still byte-identical to `src/README.md`,
#      and are the cJSON copyright notices still where NOTICE.md says they are?
#   4. Is the compiled source still upstream's own library source list?
#   5. Is the version the build graph compiled against still the version the
#      records name?
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs a target binary; it is the check that an edit to the canonical native
# source cannot pass as a routine change.
#
# Usage: tools/check-provenance.sh   (run from anywhere in the repository)
#
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
    echo "$1" >&2
    exit 1
}

digest_of() {
    # The digest of one path, with the same spelling sha256sum would print.
    sha256sum "$1" | cut -d' ' -f1
}

# 1. Bytes. This covers both the vendored upstream tree and the fixture corpus,
# because both are in the one manifest and a fixture that changed under a test
# would be a test that stopped testing anything.
sha256sum -c --quiet UPSTREAM.sha256 || fail "a recorded file no longer matches UPSTREAM.sha256"
recorded=$(grep -c '^[0-9a-f]\{64\}  ' UPSTREAM.sha256)
echo "all $recorded recorded files match UPSTREAM.sha256"

# 2. File set. `find` on both trees against the manifest's paths: a file added
# to src/ without a digest would otherwise ship unchecked, and a file removed
# would leave the comparison one-sided.
expected_tree=$(awk '/^[0-9a-f]{64}  / { print $2 }' UPSTREAM.sha256 | grep -E '^(src|testdata)/' | LC_ALL=C sort)
actual_tree=$(find src testdata -type f | LC_ALL=C sort)
if [ "$expected_tree" != "$actual_tree" ]; then
    echo "the recorded file set differs from the tree:" >&2
    diff -u <(echo "$expected_tree") <(echo "$actual_tree") >&2 || true
    echo >&2
    echo "An intentional change to the native source needs an observed failure, a" >&2
    echo "small causal patch, an explicit per-file deviation record in NOTICE.md," >&2
    echo "updated digests here, and a CHANGELOG.md entry in the same change." >&2
    exit 1
fi
echo "the file set is exactly the recorded $recorded files"

# 3a. The release digest must be recorded identically in both records, so the
# two files cannot disagree about which upstream release this is.
# `-m1` rather than a pipe into `head -1`: with `pipefail` a `head` that closes
# the pipe early sends SIGPIPE to grep and turns a successful match into a
# failed pipeline.
digest_md=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.md)
digest_list=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.sha256)
[ -n "$digest_md" ] || fail "UPSTREAM.md records no sha256 digest"
[ "$digest_md" = "$digest_list" ] ||
    fail "UPSTREAM.md and UPSTREAM.sha256 name different release digests"
echo "the release digest is recorded consistently: $digest_md"

# 3b. The preserved upstream README. README.upstream.md is the exact bytes of
# the release's README; the copy under src/ is the imported original.
cmp -s src/README.md README.upstream.md ||
    fail "README.upstream.md is no longer byte-identical to src/README.md"
echo "README.upstream.md is byte-identical to the imported upstream README"

# 3c. cJSON's own grant, in the files that carry it and in the records. The
# library headers and sources carry it, `src/LICENSE` is the text itself, and
# the fork's own records have to name it too: a private repository removes no
# upstream obligation.
for file in src/cJSON.h src/cJSON.c src/cJSON_Utils.h src/cJSON_Utils.c src/LICENSE; do
    grep -q 'Copyright (c) 2009-2017 Dave Gamble and cJSON contributors' "$file" ||
        fail "the cJSON copyright notice is missing from $file"
done
for file in NOTICE.md README.md FORK-LICENSE.md UPSTREAM.md; do
    grep -q 'Copyright (c) 2009-2017 Dave Gamble and cJSON contributors' "$file" ||
        fail "the upstream copyright notice is missing from $file"
done
grep -q 'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND' src/LICENSE ||
    fail "src/LICENSE does not reproduce the MIT permission and warranty text"
grep -q 'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND' FORK-LICENSE.md ||
    fail "FORK-LICENSE.md does not reproduce the MIT permission and warranty text"
echo "the upstream MIT notice is present in the compiled sources and in the records"

# 3d. The vendored third-party material keeps its own notices. Unity is MIT and
# says so in its own source headers, referring to a `license.txt` that this
# release ships under `docs/`; the JSON Patch corpus is Apache-2.0 by its own
# `package.json` and carries a copyright line in its README. None of those is
# covered by cJSON's notice, which is why they are checked by name.
grep -q 'Copyright (c) 2007-14 Mike Karlesky, Mark VanderVoord, Greg Williams' \
    src/tests/unity/src/unity.c ||
    fail "Unity's copyright notice is missing from src/tests/unity/src/unity.c"
[ -f src/tests/unity/docs/license.txt ] ||
    fail "src/tests/unity/docs/license.txt, the file Unity's headers refer to, is gone"
grep -q '"license": "Apache-2.0"' src/tests/json-patch-tests/package.json ||
    fail "the JSON Patch corpus no longer declares its Apache-2.0 licence"
grep -q 'Copyright (c) 2010 James Grenning and Contributed to Unity Project' \
    src/tests/unity/extras/fixture/src/unity_fixture.c ||
    fail "the Unity fixture's own contributor notice is missing"
grep -q 'Copyright (c) 2015 Alexander Mueller / XelaRellum@web.de' \
    src/tests/unity/auto/unity_test_summary.py ||
    fail "the Unity summary script's own contributor notice is missing"
echo "the vendored Unity and JSON Patch notices are present"

# 4. The compiled source is upstream's own library source list. `src/CMakeLists.txt:101`
# is `set(SOURCES cJSON.c)`, and the compiled translation unit has to be that
# file: a build that compiled something else would be a different library under
# the same name, and this is the cheapest place to notice that the records and
# the source have parted company.
grep -q '^set(SOURCES cJSON.c)$' src/CMakeLists.txt ||
    fail "src/CMakeLists.txt no longer names cJSON.c as the library source"
[ "$(digest_of src/cJSON.c)" = "$(awk '/^[0-9a-f]{64}  src\/cJSON.c$/ { print $1 }' UPSTREAM.sha256)" ] ||
    fail "src/cJSON.c does not match its recorded digest"
echo "the compiled source is upstream's cJSON.c, unmodified"

# 5. The version the header carries and the version the records name are one
# fact. `src/cJSON.c:120-122` refuses to build unless these three macros are
# 1, 7 and 19, so a divergence here is a build that would not compile rather
# than a quiet mismatch.
grep -q '^#define CJSON_VERSION_MAJOR 1$' src/cJSON.h ||
    fail "src/cJSON.h no longer declares CJSON_VERSION_MAJOR 1"
grep -q '^#define CJSON_VERSION_MINOR 7$' src/cJSON.h ||
    fail "src/cJSON.h no longer declares CJSON_VERSION_MINOR 7"
grep -q '^#define CJSON_VERSION_PATCH 19$' src/cJSON.h ||
    fail "src/cJSON.h no longer declares CJSON_VERSION_PATCH 19"
grep -q '.version = "1.7.19",' build.zig.zon ||
    fail "build.zig.zon .version is no longer 1.7.19"
grep -q 'Version: {f}' build.zig ||
    fail "build.zig no longer writes the version into cjson.pc"
echo "the header, the manifest and the pkg-config record all name 1.7.19"

# 6. The fixture corpus is byte-identical to the sibling package's, which is
# what lets two independent JSON libraries be tested on the same documents. The
# digests below are the ones both packages record; a change on one side has to
# be made on the other in the same commit or this check fails.
declare -A shared_fixtures=(
    [rfc8259/13-array.json]=43edea63643362742b9e300058d9c36c28de87ee64ec287a1292ba062e743ebf
    [rfc8259/13-object.json]=bbba38f2f20f16294f5d4bc9776fd6d46cddd24c328346b73c16251d4328cfb7
    [rfc8259/13-value-boolean.json]=a17fcf0a2f50e2d495e4f90ce263410edc183add6c62699a2facbccf60410f74
    [rfc8259/13-value-number.json]=084c799cd551dd1d8d5c5f9a5d593b2e931f5e36122ee5c793c1d08a19839cc0
    [rfc8259/13-value-string.json]=9c66babe011cad066151baf9adfff84e12c880f1700f0d754fd1214cc8d8d354
    [large/twitter.json]=30721e496a8d73cfc50658923c34eb2c0fbe15ee6835005e43ee624d8dedf200
    [values/duplicate-keys.json]=cff1405129f5eb6f87bbd8893861821ef5b693928a493fe00c8ede05392502d6
    [values/leading-zero.json]=50fd3a22758275a26064a02aa37acdcd132a84343ed5d4c00a4860d0347a45e8
    [values/nesting-2048.json]=b9dd3c2f4fac3bdf0b1e0ee6cf090dced6f26b12ff5e76e090d767e424600027
    [values/nesting-32.json]=90e02703e5a51410e9b31d64c990c5cbead97c0eb1518d89b97dbfd4cfc8834b
    [values/nesting-64.json]=55507d7345408c4e42e5941a452b0f78058b69fbd31452142affff31caf6f763
    [values/number-grammar.json]=51ab25b872725f38e6127e3b91dc3c80188e9f4f77b189352ba508c269c2ff70
    [values/string-escapes.json]=e32483a5fb73265632b1fe30e3353a0dad22d0f5afe3d6277c5312b2c74f8587
    [values/unescaped-control-character.json]=66698c0003caebed0a40253345310b332ad4580a5c018df26725a932de398482
)
for path in "${!shared_fixtures[@]}"; do
    actual=$(digest_of "testdata/$path")
    [ "$actual" = "${shared_fixtures[$path]}" ] ||
        fail "testdata/$path is $actual, which is not the digest both packages record"
done
echo "the shared fixtures still match the digests the sibling package records"

echo "provenance checks passed"