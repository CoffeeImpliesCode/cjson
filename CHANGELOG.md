# Changelog

- Port to Zig 0.17.0.

## 1.7.19

- Added a Zig 0.16.0 package for cJSON 1.7.19 with `libcjson`, the `cjson` module, and static or shared linkage.
- Added an ownership-aware Zig API for parsing, printing, JSON construction, and document mutation.
- Added optional runtime loading with version, allocator, layout, numeric-width, and error-position checks.
- Shared builds use upstream's soname, `libcjson.so.1`.
