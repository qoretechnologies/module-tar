/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file tar-module.cpp tar module implementation */
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

#include "tar-module.h"
#include "QC_TarFile.h"
#include "QC_TarEntry.h"
#include "QC_TarInputStream.h"
#include "QC_TarOutputStream.h"

#include <cstring>
#include <locale.h>

static QoreStringNode* tar_module_init();
static void tar_module_ns_init(QoreNamespace* rns, QoreNamespace* qns);
static void tar_module_delete();

DLLEXPORT char qore_module_name[] = "tar";
DLLEXPORT char qore_module_version[] = "1.0.0";
DLLEXPORT char qore_module_description[] = "Qore TAR archive module";
DLLEXPORT char qore_module_author[] = "Qore Technologies, s.r.o.";
DLLEXPORT char qore_module_url[] = "https://github.com/qorelanguage/module-tar";
DLLEXPORT int qore_module_api_major = QORE_MODULE_API_MAJOR;
DLLEXPORT int qore_module_api_minor = QORE_MODULE_API_MINOR;
DLLEXPORT qore_module_init_t qore_module_init = tar_module_init;
DLLEXPORT qore_module_ns_init_t qore_module_ns_init = tar_module_ns_init;
DLLEXPORT qore_module_delete_t qore_module_delete = tar_module_delete;
DLLEXPORT qore_license_t qore_module_license = QL_MIT;
DLLEXPORT char qore_module_license_str[] = "MIT";

// Global hashdecl pointers
const TypedHashDecl* hashdeclTarEntryInfo = nullptr;
const TypedHashDecl* hashdeclTarAddOptions = nullptr;
const TypedHashDecl* hashdeclTarExtractOptions = nullptr;
const TypedHashDecl* hashdeclTarCreateOptions = nullptr;

QoreNamespace TarNS("Tar");

static QoreStringNode* tar_module_init() {
    // Set locale to support UTF-8 filenames in archives
    setlocale(LC_ALL, "");

    // Initialize hashdecls (defined in QPP files for documentation)
    hashdeclTarEntryInfo = init_hashdecl_TarEntryInfo(TarNS);
    hashdeclTarAddOptions = init_hashdecl_TarAddOptions(TarNS);
    hashdeclTarExtractOptions = init_hashdecl_TarExtractOptions(TarNS);
    hashdeclTarCreateOptions = init_hashdecl_TarCreateOptions(TarNS);

    // Initialize classes - stream classes must be initialized before TarFile
    // because TarFile references them as return types
    TarNS.addSystemClass(initTarInputStreamClass(TarNS));
    TarNS.addSystemClass(initTarOutputStreamClass(TarNS));
    TarNS.addSystemClass(initTarFileClass(TarNS));
    TarNS.addSystemClass(initTarEntryClass(TarNS));

    return nullptr;
}

static void tar_module_ns_init(QoreNamespace* rns, QoreNamespace* qns) {
    qns->addNamespace(TarNS.copy());
}

static void tar_module_delete() {
    // Cleanup if needed
}

// Helper function to get libarchive error message
const char* get_archive_error(struct archive* a) {
    const char* err = archive_error_string(a);
    return err ? err : "unknown error";
}

// Helper function to convert compression method constant to libarchive filter
int compression_method_to_filter(int method) {
    switch (method) {
        case TAR_CM_NONE:
            return ARCHIVE_FILTER_NONE;
        case TAR_CM_GZIP:
            return ARCHIVE_FILTER_GZIP;
        case TAR_CM_BZIP2:
            return ARCHIVE_FILTER_BZIP2;
        case TAR_CM_XZ:
            return ARCHIVE_FILTER_XZ;
        case TAR_CM_ZSTD:
            return ARCHIVE_FILTER_ZSTD;
        case TAR_CM_LZ4:
            return ARCHIVE_FILTER_LZ4;
        default:
            return ARCHIVE_FILTER_NONE;
    }
}

// Helper function to convert format constant to libarchive format
int format_to_archive_format(int format) {
    switch (format) {
        case TAR_FORMAT_USTAR:
            return ARCHIVE_FORMAT_TAR_USTAR;
        case TAR_FORMAT_PAX:
            return ARCHIVE_FORMAT_TAR_PAX_INTERCHANGE;
        case TAR_FORMAT_GNU:
            return ARCHIVE_FORMAT_TAR_GNUTAR;
        case TAR_FORMAT_V7:
            return ARCHIVE_FORMAT_TAR;
        default:
            return ARCHIVE_FORMAT_TAR_PAX_INTERCHANGE;
    }
}

// Helper function to detect compression from filename
int detect_compression_from_filename(const char* filename) {
    if (!filename) {
        return TAR_CM_NONE;
    }

    size_t len = strlen(filename);
    if (len < 4) {
        return TAR_CM_NONE;
    }

    // Check for common extensions
    if (len >= 7 && strcmp(filename + len - 7, ".tar.gz") == 0) {
        return TAR_CM_GZIP;
    }
    if (len >= 4 && strcmp(filename + len - 4, ".tgz") == 0) {
        return TAR_CM_GZIP;
    }
    if (len >= 8 && strcmp(filename + len - 8, ".tar.bz2") == 0) {
        return TAR_CM_BZIP2;
    }
    if (len >= 5 && strcmp(filename + len - 5, ".tbz2") == 0) {
        return TAR_CM_BZIP2;
    }
    if (len >= 4 && strcmp(filename + len - 4, ".tbz") == 0) {
        return TAR_CM_BZIP2;
    }
    if (len >= 7 && strcmp(filename + len - 7, ".tar.xz") == 0) {
        return TAR_CM_XZ;
    }
    if (len >= 4 && strcmp(filename + len - 4, ".txz") == 0) {
        return TAR_CM_XZ;
    }
    if (len >= 8 && strcmp(filename + len - 8, ".tar.zst") == 0) {
        return TAR_CM_ZSTD;
    }
    if (len >= 9 && strcmp(filename + len - 9, ".tar.zstd") == 0) {
        return TAR_CM_ZSTD;
    }
    if (len >= 8 && strcmp(filename + len - 8, ".tar.lz4") == 0) {
        return TAR_CM_LZ4;
    }
    if (len >= 4 && strcmp(filename + len - 4, ".tar") == 0) {
        return TAR_CM_NONE;
    }

    return TAR_CM_NONE;
}
