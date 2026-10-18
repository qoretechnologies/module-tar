/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file tar-module.h tar module header file */
/*
    Qore tar module

    Copyright (C) 2026 Qore Technologies, s.r.o.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
*/

#ifndef _QORE_TAR_MODULE_H
#define _QORE_TAR_MODULE_H

#include <qore/Qore.h>
#include <qore/QoreSandboxManager.h>
#include <archive.h>
#include <archive_entry.h>

#include <locale.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif

#include <string>

//! Runs libarchive on the calling thread under a UTF-8 character type locale
/** Tar (pax) headers store names in UTF-8, and libarchive converts every name between UTF-8 and the
    character set of the current locale.  In the "C" locale, which Qore programs and services often run in,
    a non-ASCII name could be neither written nor read (and libarchive's UTF-8 name setters crashed).  Each
    module call that uses libarchive therefore switches only its own thread to a UTF-8 locale and restores
    the thread's previous locale when it returns; the process locale is never changed.  When no UTF-8
    locale exists on the host, the thread's locale is left as it is.
*/
class TarUtf8LocaleHelper {
public:
    DLLLOCAL TarUtf8LocaleHelper() : previous(get() ? uselocale(get()) : (locale_t)0) {
    }

    DLLLOCAL ~TarUtf8LocaleHelper() {
        if (previous) {
            uselocale(previous);
        }
    }

    //! Runs code that may not need a UTF-8 locale (Qore callbacks) under the thread's own locale
    class Suspend {
    public:
        DLLLOCAL Suspend() : current(uselocale(LC_GLOBAL_LOCALE)) {
        }

        DLLLOCAL ~Suspend() {
            uselocale(current);
        }

    private:
        //! the locale in effect on the thread before the callback
        locale_t current;
    };

private:
    locale_t previous;

    //! Returns the UTF-8 locale, created once for the process, or 0 if the host has none
    DLLLOCAL static locale_t get() {
        static locale_t utf8 = create();
        return utf8;
    }

    DLLLOCAL static locale_t create() {
        for (const char* name : {"C.UTF-8", "C.utf8", "en_US.UTF-8", "UTF-8"}) {
            locale_t loc = newlocale(LC_CTYPE_MASK, name, (locale_t)0);
            if (loc) {
                return loc;
            }
        }
        return (locale_t)0;
    }
};

//! Returns a UTF-8 string in Unicode Normalization Form C (canonical composition)
/** libarchive normalizes the UTF-8 names of pax headers when it reads them: to NFD on macOS, and to NFC on other
    platforms; the names of ustar and GNU headers are read as they are stored.  A name can therefore not be read
    exactly as it is stored, and the module presents entry names, link targets and owner names, and compares
    names, in NFC on every platform.  On macOS the string is normalized with CoreFoundation; elsewhere with
    libarchive's own normalization, which needs the UTF-8 locale of @ref TarUtf8LocaleHelper.

    @param str the UTF-8 string, or nullptr

    @return the string in NFC; a string that cannot be normalized, such as one that is not valid UTF-8, is returned
    as it is, and nullptr gives an empty string
*/
DLLLOCAL std::string tar_nfc(const char* str);

//! Returns an entry's path name as libarchive read it, in UTF-8, or nullptr
/** The locale-dependent libarchive accessors cannot convert a non-ASCII name in the "C" locale, so a name
    such as a Japanese file name was unreadable; the raw name is the fallback for an archive written with an
    undeclared legacy encoding.
*/
static inline const char* tar_entry_pathname_raw(struct archive_entry* entry) {
    const char* name = archive_entry_pathname_utf8(entry);
    return name ? name : archive_entry_pathname(entry);
}

//! Returns an entry's symbolic link target as libarchive read it, in UTF-8, or nullptr
static inline const char* tar_entry_symlink_raw(struct archive_entry* entry) {
    const char* target = archive_entry_symlink_utf8(entry);
    return target ? target : archive_entry_symlink(entry);
}

//! Returns an entry's hard link target as libarchive read it, in UTF-8, or nullptr
static inline const char* tar_entry_hardlink_raw(struct archive_entry* entry) {
    const char* target = archive_entry_hardlink_utf8(entry);
    return target ? target : archive_entry_hardlink(entry);
}

//! Returns an entry's path name in NFC (see tar_nfc())
static inline std::string tar_entry_pathname(struct archive_entry* entry) {
    return tar_nfc(tar_entry_pathname_raw(entry));
}

// Forward declarations
class QoreTarFile;

// Hashdecl init functions (generated by QPP from QC_TarFile.qpp)
DLLLOCAL TypedHashDecl* init_hashdecl_TarEntryInfo(QoreNamespace& ns);
DLLLOCAL TypedHashDecl* init_hashdecl_TarAddOptions(QoreNamespace& ns);
DLLLOCAL TypedHashDecl* init_hashdecl_TarExtractOptions(QoreNamespace& ns);
DLLLOCAL TypedHashDecl* init_hashdecl_TarCreateOptions(QoreNamespace& ns);

// Compression methods
#define TAR_CM_NONE     0   // No compression (.tar)
#define TAR_CM_GZIP     1   // Gzip compression (.tar.gz, .tgz)
#define TAR_CM_BZIP2    2   // Bzip2 compression (.tar.bz2)
#define TAR_CM_XZ       3   // XZ/LZMA compression (.tar.xz)
#define TAR_CM_ZSTD     4   // Zstandard compression (.tar.zst)
#define TAR_CM_LZ4      5   // LZ4 compression (.tar.lz4)

// Compression levels
#define TAR_COMPRESSION_DEFAULT -1
#define TAR_COMPRESSION_FASTEST 1
#define TAR_COMPRESSION_BEST    9

// Tar formats
#define TAR_FORMAT_USTAR    0   // POSIX.1-1988 ustar
#define TAR_FORMAT_PAX      1   // POSIX.1-2001 pax (default)
#define TAR_FORMAT_GNU      2   // GNU tar format
#define TAR_FORMAT_V7       3   // Old V7 tar

// Mode constants
enum TarMode {
    TAR_MODE_READ,
    TAR_MODE_WRITE,
    TAR_MODE_APPEND
};

// Global hashdecl pointers (initialized in tar-module.cpp)
extern const TypedHashDecl* hashdeclTarEntryInfo;
extern const TypedHashDecl* hashdeclTarAddOptions;
extern const TypedHashDecl* hashdeclTarExtractOptions;
extern const TypedHashDecl* hashdeclTarCreateOptions;

// Namespace
extern QoreNamespace TarNS;

// Helper function to get libarchive error message
DLLLOCAL const char* get_archive_error(struct archive* a);

// Helper function to convert compression method constant to libarchive filter
DLLLOCAL int compression_method_to_filter(int method);

// Helper function to convert format constant to libarchive format
DLLLOCAL int format_to_archive_format(int format);

// Helper function to detect compression from filename
DLLLOCAL int detect_compression_from_filename(const char* filename);

#endif // _QORE_TAR_MODULE_H
