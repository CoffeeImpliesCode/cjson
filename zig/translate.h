/* The one header this package translates.
 *
 * `zig build` runs translate-c over this file, and what that translation
 * becomes is the `c` module the Zig facade in `zig/root.zig` imports. Its whole
 * job is to name the public header of the library this build compiles and
 * include it whole.
 *
 * Which header that is
 * -------------------
 * cJSON installs two public headers, and this file names one of them:
 *
 *   cJSON.h  the library. It includes `<stddef.h>` itself
 *            (src/cJSON.h:86) and nothing else, so the only declaration surface
 *            it adds to a translation is cJSON's own: the `cJSON` struct
 *            (src/cJSON.h:103-123), the `cJSON_Hooks` struct
 *            (src/cJSON.h:125-130), the `cJSON_bool` typedef
 *            (src/cJSON.h:132), the version macros (src/cJSON.h:82-84), the type
 *            bits (src/cJSON.h:89-100) and every `CJSON_PUBLIC` declaration.
 *
 * It is included whole, with its own include guard, so this wrapper cannot
 * disagree with the real header by omission and cannot re-declare a prototype
 * with a different type.
 *
 * Why cJSON_Utils.h is not listed
 * -------------------------------
 * Because no artifact this package builds implements it, and translating its
 * declarations would publish a `cJSONUtils_*` surface that nothing here
 * provides. Upstream builds those functions into a *separate* library target
 * with its own soname (`src/CMakeLists.txt:13`, `:213-221`), and this package
 * compiles upstream's library source list exactly (`src/CMakeLists.txt:101`).
 * The file is vendored, unmodified and uncompiled; UPSTREAM.md, "What is
 * compiled and what is not", states the boundary and `build.zig` keeps it.
 *
 * Why the macros of this build are not here
 * ----------------------------------------
 * A copy of any declaration, and no macro of this build's own.
 *
 * `ENABLE_LOCALES` and `CJSON_API_VISIBILITY` are on the compile line, not
 * here, and not in the header, because they describe *this* build's
 * configuration rather than what the interface is -- the same reason upstream
 * puts them in `add_definitions` in `src/CMakeLists.txt` and not in `cJSON.h`.
 * They are defined once in `build.zig` and given to the library's own
 * compilation and to this translation alike, so the declarations below and the
 * code that implements them cannot be built for two different configurations.
 *
 * `CJSON_IMPORT_SYMBOLS` is the one macro a *consumer* of a shared build may
 * need, and it is deliberately absent here: it turns `CJSON_PUBLIC` from
 * `dllexport` into `dllimport` (src/cJSON.h:63-69), which is a fact about how
 * the library was built rather than about the interface. `build.zig` puts
 * `CJSON_EXPORT_SYMBOLS` (with `CJSON_API_VISIBILITY`) on the compile lines for
 * the library and for this translation, and the installed `cjson.pc` carries
 * `CJSON_IMPORT_SYMBOLS` in `Cflags` for a shared install, which is how a C
 * consumer gets the same `dllimport` answer without repeating the flag.
 *
 * On every non-Windows target those two Windows macros change nothing:
 * `src/cJSON.h:70-79` takes the `__WINDOWS__`-less branch, where
 * `CJSON_API_VISIBILITY` is the only one of the three that is read.
 */

#ifndef CJSON_TRANSLATE_H
#define CJSON_TRANSLATE_H

#include <cJSON.h>

#endif /* CJSON_TRANSLATE_H */