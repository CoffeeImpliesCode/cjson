# Upstream

| Field | Value |
|---|---|
| Project | cJSON — <https://github.com/DaveGamble/cJSON> |
| Release | `v1.7.19`, published 2025-09-09T13:58:05Z |
| Tag commit | `c859b25da02955fef659d658b8f324b5cde87be3`, dated 2025-09-09T13:56:10Z |
| Release archive | <https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.19.tar.gz> (356,247 bytes) |
| Archive SHA-256 | `7fa616e3046edfa7a28a32d5f9eacfd23f92900fe1f8ccd988c1662f30454562` |
| Source version | 1.7.19, declared by `src/cJSON.h` and `src/CMakeLists.txt` |
| cJSON licence | MIT; `src/LICENSE`. Third-party exceptions are listed in `NOTICE.md`. |
| Imported tree | `src/`: 216 files from the release, unchanged. |
| Removed upstream files | None. |
| File digests | `UPSTREAM.sha256`. |

The source was obtained from the official GitHub release archive and extracted into `src/`.

`src/cJSON.c` is the only compiled upstream source. `src/cJSON_Utils.c` and `src/cJSON_Utils.h` are retained but not compiled; upstream builds them as a separate library.

Copyright (c) 2009-2017 Dave Gamble and cJSON contributors

The upstream MIT grant is preserved in `src/LICENSE`.

## Fixture provenance

| Paths | Origin |
|---|---|
| `testdata/rfc8259/*` | Five examples from RFC 8259 §13: <https://www.rfc-editor.org/rfc/rfc8259.txt>. The plain-text layout adds six leading spaces to preformatted lines; each transcription removes those spaces and adds one trailing newline. |
| `testdata/large/twitter.json` | Byte-identical to `jsonexamples/twitter.json` from simdjson 5.0.2; 631,515 bytes; SHA-256 `30721e496a8d73cfc50658923c34eb2c0fbe15ee6835005e43ee624d8dedf200`. |
| `testdata/malformed/*.json`, `testdata/values/*.json` | Authored for this package; file digests are in `UPSTREAM.sha256`. |
