/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file QoreTarFile.cpp QoreTarFile class implementation */
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

#include "QoreTarFile.h"
#include "TarInputStream.h"
#include "TarOutputStream.h"
#include "QC_TarInputStream.h"
#include "QC_TarOutputStream.h"

#include <sys/stat.h>
#include <cstring>
#include <algorithm>
#include <memory>

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#endif

// Helper function to compare entry names with Unicode normalization support
// On macOS, libarchive returns pathnames in NFD (decomposed) form, so we need
// to normalize both strings before comparison
static bool entryNameEquals(const char* archive_name, const char* lookup_name) {
#ifdef __APPLE__
    // On macOS, normalize both strings to NFD for comparison
    CFStringRef archiveStr = CFStringCreateWithCString(kCFAllocatorDefault, archive_name, kCFStringEncodingUTF8);
    CFStringRef lookupStr = CFStringCreateWithCString(kCFAllocatorDefault, lookup_name, kCFStringEncodingUTF8);

    if (!archiveStr || !lookupStr) {
        // Fallback to byte comparison if conversion fails
        if (archiveStr) CFRelease(archiveStr);
        if (lookupStr) CFRelease(lookupStr);
        return strcmp(archive_name, lookup_name) == 0;
    }

    // Create mutable copies for normalization
    CFMutableStringRef archiveMutable = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, archiveStr);
    CFMutableStringRef lookupMutable = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, lookupStr);

    CFRelease(archiveStr);
    CFRelease(lookupStr);

    if (!archiveMutable || !lookupMutable) {
        if (archiveMutable) CFRelease(archiveMutable);
        if (lookupMutable) CFRelease(lookupMutable);
        return strcmp(archive_name, lookup_name) == 0;
    }

    // Normalize both to NFD (decomposed form)
    CFStringNormalize(archiveMutable, kCFStringNormalizationFormD);
    CFStringNormalize(lookupMutable, kCFStringNormalizationFormD);

    // Compare
    CFComparisonResult result = CFStringCompare(archiveMutable, lookupMutable, 0);

    CFRelease(archiveMutable);
    CFRelease(lookupMutable);

    return result == kCFCompareEqualTo;
#else
    // On other platforms, use simple byte comparison
    return strcmp(archive_name, lookup_name) == 0;
#endif
}

// RAII wrapper for FILE*
class FileHandle {
public:
    explicit FileHandle(FILE* f = nullptr) : fp(f) {}
    ~FileHandle() { if (fp) fclose(fp); }
    FileHandle(const FileHandle&) = delete;
    FileHandle& operator=(const FileHandle&) = delete;
    FILE* get() const { return fp; }
    explicit operator bool() const { return fp != nullptr; }
private:
    FILE* fp;
};

// RAII wrapper for archive_entry*
class ArchiveEntryGuard {
public:
    explicit ArchiveEntryGuard(struct archive_entry* e = nullptr) : entry(e) {}
    ~ArchiveEntryGuard() { if (entry) archive_entry_free(entry); }
    ArchiveEntryGuard(const ArchiveEntryGuard&) = delete;
    ArchiveEntryGuard& operator=(const ArchiveEntryGuard&) = delete;
    struct archive_entry* get() const { return entry; }
    struct archive_entry* release() { auto e = entry; entry = nullptr; return e; }
    explicit operator bool() const { return entry != nullptr; }
private:
    struct archive_entry* entry;
};

// Helper function to check for path traversal attacks
// Returns true if path is safe, false if it contains dangerous components
static bool isPathSafe(const char* path) {
    if (!path || !*path) {
        return true;  // Empty path is safe
    }

    // Check for absolute paths
    if (path[0] == '/') {
        return false;
    }

    // Check for Windows absolute paths
    if ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) {
        if (path[1] == ':') {
            return false;
        }
    }

    // Check for path traversal sequences
    const char* p = path;
    while (*p) {
        // Check for ".." component
        if (p[0] == '.' && p[1] == '.') {
            // Make sure it's actually a ".." path component
            if ((p == path || p[-1] == '/' || p[-1] == '\\') &&
                (p[2] == '\0' || p[2] == '/' || p[2] == '\\')) {
                return false;
            }
        }
        p++;
    }

    return true;
}

// Buffer size for reading/writing
#define TAR_BUFFER_SIZE 65536

// Constructor for file-based archive
QoreTarFile::QoreTarFile(const char* path, TarMode mode, int compression_method, int format, ExceptionSink* xsink)
    : filepath(path), mode(mode), read_archive(nullptr), write_archive(nullptr),
      compression_method(compression_method), compression_level(-1), format(format), in_memory(false), closed(false),
      memory_pos(0), input_stream(nullptr), output_stream(nullptr) {

    // Auto-detect compression from filename if not specified
    if (compression_method < 0) {
        this->compression_method = detect_compression_from_filename(path);
    }

    if (mode == TAR_MODE_READ) {
        openRead(xsink);
    } else if (mode == TAR_MODE_APPEND) {
        openAppend(xsink);
    } else {
        openWrite(xsink);
    }
}

// Constructor for in-memory archive (from binary data)
QoreTarFile::QoreTarFile(const BinaryNode* data, ExceptionSink* xsink)
    : mode(TAR_MODE_READ), read_archive(nullptr), write_archive(nullptr),
      compression_method(TAR_CM_NONE), compression_level(-1), format(TAR_FORMAT_PAX), in_memory(true), closed(false),
      memory_pos(0), input_stream(nullptr), output_stream(nullptr) {

    if (data && data->size() > 0) {
        memory_buffer.resize(data->size());
        memcpy(memory_buffer.data(), data->getPtr(), data->size());
    }
    openRead(xsink);
}

// Constructor for new in-memory archive
QoreTarFile::QoreTarFile(int compression_method, int format, ExceptionSink* xsink)
    : mode(TAR_MODE_WRITE), read_archive(nullptr), write_archive(nullptr),
      compression_method(compression_method >= 0 ? compression_method : TAR_CM_NONE),
      compression_level(-1), format(format >= 0 ? format : TAR_FORMAT_PAX), in_memory(true), closed(false),
      memory_pos(0), input_stream(nullptr), output_stream(nullptr) {

    openWrite(xsink);
}

// Constructor for stream-based reading
QoreTarFile::QoreTarFile(InputStream* input, ExceptionSink* xsink)
    : mode(TAR_MODE_READ), read_archive(nullptr), write_archive(nullptr),
      compression_method(TAR_CM_NONE), compression_level(-1), format(TAR_FORMAT_PAX), in_memory(false), closed(false),
      memory_pos(0), input_stream(input), output_stream(nullptr) {

    if (input) {
        input->ref();
    }
    openRead(xsink);
}

// Constructor for stream-based writing
QoreTarFile::QoreTarFile(OutputStream* output, int compression_method, int format, ExceptionSink* xsink)
    : mode(TAR_MODE_WRITE), read_archive(nullptr), write_archive(nullptr),
      compression_method(compression_method >= 0 ? compression_method : TAR_CM_NONE),
      compression_level(-1), format(format >= 0 ? format : TAR_FORMAT_PAX), in_memory(false), closed(false),
      memory_pos(0), input_stream(nullptr), output_stream(output) {

    if (output) {
        output->ref();
    }
    openWrite(xsink);
}

// Destructor
QoreTarFile::~QoreTarFile() {
    ExceptionSink xsink;
    if (!closed) {
        close(&xsink);
    }
    if (input_stream) {
        input_stream->deref(&xsink);
    }
    if (output_stream) {
        output_stream->deref(&xsink);
    }
}

// Close the archive
void QoreTarFile::close(ExceptionSink* xsink) {
    if (closed) {
        return;
    }

    if (read_archive) {
        archive_read_close(read_archive);
        archive_read_free(read_archive);
        read_archive = nullptr;
    }

    if (write_archive) {
        archive_write_close(write_archive);
        archive_write_free(write_archive);
        write_archive = nullptr;
    }

    closed = true;
}

// Get archive as binary data
BinaryNode* QoreTarFile::toData(ExceptionSink* xsink) {
    if (!in_memory) {
        xsink->raiseException("TAR-ERROR", "cannot get binary data from file-based archive");
        return nullptr;
    }

    if (mode == TAR_MODE_WRITE && write_archive) {
        // Close write archive to finalize data
        archive_write_close(write_archive);
        archive_write_free(write_archive);
        write_archive = nullptr;
    }

    if (memory_buffer.empty()) {
        return new BinaryNode();
    }

    // Create a copy of the data - BinaryNode takes ownership of passed memory
    BinaryNode* result = new BinaryNode();
    result->append(memory_buffer.data(), memory_buffer.size());
    return result;
}

// Open for reading
void QoreTarFile::openRead(ExceptionSink* xsink) {
    read_archive = archive_read_new();
    if (!read_archive) {
        xsink->raiseException("TAR-ERROR", "failed to create archive reader");
        return;
    }

    // Support all formats and compression filters
    archive_read_support_format_all(read_archive);
    archive_read_support_filter_all(read_archive);

    int r;
    if (in_memory) {
        if (memory_buffer.empty()) {
            // Empty archive, nothing to read
            return;
        }
        r = archive_read_open_memory(read_archive, memory_buffer.data(), memory_buffer.size());
    } else if (input_stream) {
        r = archive_read_open(read_archive, this, nullptr, stream_read_callback, stream_close_callback);
    } else {
        r = archive_read_open_filename(read_archive, filepath.c_str(), TAR_BUFFER_SIZE);
    }

    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to open archive for reading: %s",
                              get_archive_error(read_archive));
        archive_read_free(read_archive);
        read_archive = nullptr;
    }
}

// Open for writing
void QoreTarFile::openWrite(ExceptionSink* xsink) {
    write_archive = archive_write_new();
    if (!write_archive) {
        xsink->raiseException("TAR-ERROR", "failed to create archive writer");
        return;
    }

    // Set format
    int archive_format = format_to_archive_format(format);
    if (archive_write_set_format(write_archive, archive_format) != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to set archive format: %s",
                              get_archive_error(write_archive));
        archive_write_free(write_archive);
        write_archive = nullptr;
        return;
    }

    // Setup compression filter
    setupCompressionFilter(xsink);
    if (*xsink) {
        archive_write_free(write_archive);
        write_archive = nullptr;
        return;
    }

    int r;
    if (in_memory) {
        r = archive_write_open(write_archive, this, nullptr, memory_write_callback, memory_close_callback);
    } else if (output_stream) {
        r = archive_write_open(write_archive, this, nullptr, stream_write_callback, stream_close_callback);
    } else {
        r = archive_write_open_filename(write_archive, filepath.c_str());
    }

    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to open archive for writing: %s",
                              get_archive_error(write_archive));
        archive_write_free(write_archive);
        write_archive = nullptr;
    }
}

// Open for appending - reads existing archive and prepares for writing new entries
void QoreTarFile::openAppend(ExceptionSink* xsink) {
    // For append mode, we need to:
    // 1. Read the existing archive
    // 2. Create a temporary write archive
    // 3. Copy all existing entries
    // 4. Then allow new entries to be added

    // Check if file exists
    struct stat st;
    if (stat(filepath.c_str(), &st) != 0) {
        // File doesn't exist - just open for writing
        mode = TAR_MODE_WRITE;
        openWrite(xsink);
        return;
    }

    // Read existing archive into memory
    std::vector<char> existing_data;
    FileHandle fp(fopen(filepath.c_str(), "rb"));
    if (!fp) {
        xsink->raiseException("TAR-ERROR", "failed to open archive for reading: %s", strerror(errno));
        return;
    }

    existing_data.resize(st.st_size);
    if (fread(existing_data.data(), 1, st.st_size, fp.get()) != (size_t)st.st_size) {
        xsink->raiseException("TAR-ERROR", "failed to read existing archive");
        return;
    }

    // Open read archive from memory
    read_archive = archive_read_new();
    if (!read_archive) {
        xsink->raiseException("TAR-ERROR", "failed to create archive reader");
        return;
    }

    archive_read_support_format_all(read_archive);
    archive_read_support_filter_all(read_archive);

    if (archive_read_open_memory(read_archive, existing_data.data(), existing_data.size()) != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to open existing archive: %s",
                              get_archive_error(read_archive));
        archive_read_free(read_archive);
        read_archive = nullptr;
        return;
    }

    // Open write archive to the same file (will overwrite)
    openWrite(xsink);
    if (*xsink) {
        archive_read_free(read_archive);
        read_archive = nullptr;
        return;
    }

    // Copy all existing entries
    copyEntries(xsink);

    // Close read archive - we're done with it
    archive_read_free(read_archive);
    read_archive = nullptr;

    // Now the write archive is ready for new entries
    // Mode stays as APPEND so we know we're in append mode
}

// Copy entries from read archive to write archive
void QoreTarFile::copyEntries(ExceptionSink* xsink) {
    if (!read_archive || !write_archive) {
        return;
    }

    struct archive_entry* entry;
    char buffer[TAR_BUFFER_SIZE];

    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        // Write header to new archive
        int r = archive_write_header(write_archive, entry);
        if (r != ARCHIVE_OK) {
            xsink->raiseException("TAR-ERROR", "failed to copy entry header: %s",
                                  get_archive_error(write_archive));
            return;
        }

        // Copy data if this is a regular file with content
        if (archive_entry_size(entry) > 0) {
            la_ssize_t bytes_read;
            while ((bytes_read = archive_read_data(read_archive, buffer, sizeof(buffer))) > 0) {
                if (archive_write_data(write_archive, buffer, bytes_read) < 0) {
                    xsink->raiseException("TAR-ERROR", "failed to copy entry data: %s",
                                          get_archive_error(write_archive));
                    return;
                }
            }
            if (bytes_read < 0) {
                xsink->raiseException("TAR-ERROR", "failed to read entry data: %s",
                                      get_archive_error(read_archive));
                return;
            }
        }
    }
}

// Setup compression filter
void QoreTarFile::setupCompressionFilter(ExceptionSink* xsink) {
    int r = ARCHIVE_OK;

    switch (compression_method) {
        case TAR_CM_NONE:
            r = archive_write_add_filter_none(write_archive);
            break;
        case TAR_CM_GZIP:
            r = archive_write_add_filter_gzip(write_archive);
            break;
        case TAR_CM_BZIP2:
            r = archive_write_add_filter_bzip2(write_archive);
            break;
        case TAR_CM_XZ:
            r = archive_write_add_filter_xz(write_archive);
            break;
        case TAR_CM_ZSTD:
            r = archive_write_add_filter_zstd(write_archive);
            break;
        case TAR_CM_LZ4:
            r = archive_write_add_filter_lz4(write_archive);
            break;
        default:
            xsink->raiseException("TAR-ERROR", "invalid compression method: %d", compression_method);
            return;
    }

    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to set compression filter: %s",
                              get_archive_error(write_archive));
        return;
    }

    // Set compression level if specified (1-9)
    if (compression_level >= 1 && compression_level <= 9 && compression_method != TAR_CM_NONE) {
        char level_option[32];
        const char* filter_name = nullptr;
        switch (compression_method) {
            case TAR_CM_GZIP:  filter_name = "gzip"; break;
            case TAR_CM_BZIP2: filter_name = "bzip2"; break;
            case TAR_CM_XZ:    filter_name = "xz"; break;
            case TAR_CM_ZSTD:  filter_name = "zstd"; break;
            case TAR_CM_LZ4:   filter_name = "lz4"; break;
            default: break;
        }
        if (filter_name) {
            snprintf(level_option, sizeof(level_option), "%s:compression-level=%d", filter_name, compression_level);
            r = archive_write_set_options(write_archive, level_option);
            if (r != ARCHIVE_OK && r != ARCHIVE_WARN) {
                // Non-fatal: just log warning, don't fail
            }
        }
    }
}

// Reopen archive for reading
void QoreTarFile::reopenRead(ExceptionSink* xsink) {
    if (read_archive) {
        archive_read_close(read_archive);
        archive_read_free(read_archive);
        read_archive = nullptr;
    }
    memory_pos = 0;
    openRead(xsink);
}

// Check archive is open
bool QoreTarFile::checkOpen(ExceptionSink* xsink, bool forWrite) {
    if (closed) {
        xsink->raiseException("TAR-ERROR", "archive is closed");
        return false;
    }

    if (forWrite) {
        if (!write_archive) {
            xsink->raiseException("TAR-ERROR", "archive is not open for writing");
            return false;
        }
    } else {
        if (!read_archive && !in_memory) {
            xsink->raiseException("TAR-ERROR", "archive is not open for reading");
            return false;
        }
    }

    return true;
}

// Get list of all entries
QoreListNode* QoreTarFile::entries(ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return nullptr;
    }

    // Reopen to read from beginning
    reopenRead(xsink);
    if (*xsink) {
        return nullptr;
    }

    QoreListNode* list = new QoreListNode(hashdeclTarEntryInfo->getTypeInfo());

    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        QoreHashNode* info = createEntryInfo(entry, xsink);
        if (*xsink) {
            list->deref(xsink);
            return nullptr;
        }
        list->push(info, xsink);
        archive_read_data_skip(read_archive);
    }

    return list;
}

// Get number of entries
int64 QoreTarFile::count(ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return -1;
    }

    reopenRead(xsink);
    if (*xsink) {
        return -1;
    }

    int64 count = 0;
    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        count++;
        archive_read_data_skip(read_archive);
    }

    return count;
}

// Check if entry exists
bool QoreTarFile::hasEntry(const char* name, ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return false;
    }

    reopenRead(xsink);
    if (*xsink) {
        return false;
    }

    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        if (entryNameEquals(archive_entry_pathname(entry), name)) {
            return true;
        }
        archive_read_data_skip(read_archive);
    }

    return false;
}

// Get entry info
QoreHashNode* QoreTarFile::getEntry(const char* name, ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return nullptr;
    }

    reopenRead(xsink);
    if (*xsink) {
        return nullptr;
    }

    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        if (entryNameEquals(archive_entry_pathname(entry), name)) {
            return createEntryInfo(entry, xsink);
        }
        archive_read_data_skip(read_archive);
    }

    return nullptr;  // Entry not found
}

// Read entry as binary data
BinaryNode* QoreTarFile::read(const char* name, ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return nullptr;
    }

    reopenRead(xsink);
    if (*xsink) {
        return nullptr;
    }

    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        if (entryNameEquals(archive_entry_pathname(entry), name)) {
            int64 size = archive_entry_size(entry);
            if (size <= 0) {
                return new BinaryNode();
            }

            SimpleRefHolder<BinaryNode> data(new BinaryNode());
            // Note: don't use preallocate() as it sets size, not just capacity

            char buffer[TAR_BUFFER_SIZE];
            la_ssize_t bytes_read;
            while ((bytes_read = archive_read_data(read_archive, buffer, sizeof(buffer))) > 0) {
                data->append(buffer, bytes_read);
            }

            if (bytes_read < 0) {
                xsink->raiseException("TAR-ERROR", "failed to read entry data: %s",
                                      get_archive_error(read_archive));
                return nullptr;
            }

            return data.release();
        }
        archive_read_data_skip(read_archive);
    }

    xsink->raiseException("TAR-ERROR", "entry '%s' not found", name);
    return nullptr;
}

// Read entry as text
QoreStringNode* QoreTarFile::readText(const char* name, const char* encoding, ExceptionSink* xsink) {
    SimpleRefHolder<BinaryNode> data(read(name, xsink));
    if (*xsink || !data) {
        return nullptr;
    }

    const QoreEncoding* enc = encoding ? QEM.findCreate(encoding) : QCS_DEFAULT;
    return new QoreStringNode((const char*)data->getPtr(), data->size(), enc);
}

// Create TarEntryInfo hash from archive_entry
QoreHashNode* QoreTarFile::createEntryInfo(struct archive_entry* entry, ExceptionSink* xsink) const {
    ReferenceHolder<QoreHashNode> info(new QoreHashNode(hashdeclTarEntryInfo, xsink), xsink);

    info->setKeyValue("name", new QoreStringNode(archive_entry_pathname(entry)), xsink);
    info->setKeyValue("size", archive_entry_size(entry), xsink);

    // Timestamps
    if (archive_entry_mtime_is_set(entry)) {
        info->setKeyValue("modified", DateTimeNode::makeAbsolute(currentTZ(), archive_entry_mtime(entry)), xsink);
    }
    if (archive_entry_atime_is_set(entry)) {
        info->setKeyValue("accessed", DateTimeNode::makeAbsolute(currentTZ(), archive_entry_atime(entry)), xsink);
    }
    if (archive_entry_ctime_is_set(entry)) {
        info->setKeyValue("created", DateTimeNode::makeAbsolute(currentTZ(), archive_entry_ctime(entry)), xsink);
    }

    info->setKeyValue("mode", archive_entry_mode(entry), xsink);
    info->setKeyValue("uid", (int64)archive_entry_uid(entry), xsink);
    info->setKeyValue("gid", (int64)archive_entry_gid(entry), xsink);

    const char* uname = archive_entry_uname(entry);
    if (uname) {
        info->setKeyValue("uname", new QoreStringNode(uname), xsink);
    }

    const char* gname = archive_entry_gname(entry);
    if (gname) {
        info->setKeyValue("gname", new QoreStringNode(gname), xsink);
    }

    // Determine type - check for hardlink first (hardlinks can have any filetype)
    int filetype = archive_entry_filetype(entry);
    const char* hardlink_target = archive_entry_hardlink(entry);
    const char* type_str;
    if (hardlink_target && *hardlink_target) {
        type_str = "hardlink";
    } else {
        switch (filetype) {
            case AE_IFREG:  type_str = "file"; break;
            case AE_IFDIR:  type_str = "directory"; break;
            case AE_IFLNK:  type_str = "symlink"; break;
            case AE_IFCHR:  type_str = "chardev"; break;
            case AE_IFBLK:  type_str = "blockdev"; break;
            case AE_IFIFO:  type_str = "fifo"; break;
            case AE_IFSOCK: type_str = "socket"; break;
            default:        type_str = "unknown"; break;
        }
    }
    info->setKeyValue("type", new QoreStringNode(type_str), xsink);

    // Link target
    const char* link = archive_entry_symlink(entry);
    if (!link) {
        link = archive_entry_hardlink(entry);
    }
    if (link) {
        info->setKeyValue("link_target", new QoreStringNode(link), xsink);
    }

    // Convenience flags
    info->setKeyValue("is_directory", filetype == AE_IFDIR, xsink);
    info->setKeyValue("is_symlink", filetype == AE_IFLNK, xsink);
    info->setKeyValue("is_hardlink", archive_entry_hardlink(entry) != nullptr, xsink);

    // Device numbers
    if (filetype == AE_IFCHR || filetype == AE_IFBLK) {
        info->setKeyValue("devmajor", (int64)archive_entry_devmajor(entry), xsink);
        info->setKeyValue("devminor", (int64)archive_entry_devminor(entry), xsink);
    }

    return info.release();
}

// Add binary data as entry
void QoreTarFile::add(const char* name, const BinaryNode* data, const QoreHashNode* opts, ExceptionSink* xsink) {
    if (!checkOpen(xsink, true)) {
        return;
    }

    int mode_val = 0644;
    int uid = 0, gid = 0;
    std::string uname, gname;
    int64 modified_time = 0;
    bool preserve_permissions = true;
    bool dereference_symlinks = false;

    if (opts) {
        parseAddOptions(opts, mode_val, uid, gid, uname, gname, modified_time,
                        preserve_permissions, dereference_symlinks, xsink);
        if (*xsink) {
            return;
        }
    }

    struct archive_entry* entry = archive_entry_new();
    if (!entry) {
        xsink->raiseException("TAR-ERROR", "failed to create archive entry");
        return;
    }

    archive_entry_set_pathname(entry, name);
    archive_entry_set_size(entry, data ? data->size() : 0);
    archive_entry_set_filetype(entry, AE_IFREG);
    archive_entry_set_perm(entry, mode_val);

    if (uid > 0) {
        archive_entry_set_uid(entry, uid);
    }
    if (gid > 0) {
        archive_entry_set_gid(entry, gid);
    }
    if (!uname.empty()) {
        archive_entry_set_uname(entry, uname.c_str());
    }
    if (!gname.empty()) {
        archive_entry_set_gname(entry, gname.c_str());
    }

    if (modified_time > 0) {
        archive_entry_set_mtime(entry, modified_time, 0);
    } else {
        archive_entry_set_mtime(entry, time(nullptr), 0);
    }

    int r = archive_write_header(write_archive, entry);
    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to write entry header: %s",
                              get_archive_error(write_archive));
        archive_entry_free(entry);
        return;
    }

    if (data && data->size() > 0) {
        la_ssize_t written = archive_write_data(write_archive, data->getPtr(), data->size());
        if (written < 0 || (size_t)written != data->size()) {
            xsink->raiseException("TAR-ERROR", "failed to write entry data: %s",
                                  get_archive_error(write_archive));
        }
    }

    archive_entry_free(entry);
}

// Add text as entry
void QoreTarFile::addText(const char* name, const QoreStringNode* text, const char* encoding,
                          const QoreHashNode* opts, ExceptionSink* xsink) {
    TempEncodingHelper str(text, QCS_UTF8, xsink);
    if (*xsink) {
        return;
    }

    // Create a BinaryNode with a copy of the string data
    SimpleRefHolder<BinaryNode> data(new BinaryNode());
    data->append(str->c_str(), str->size());
    add(name, *data, opts, xsink);
}

// Add file from filesystem
void QoreTarFile::addFile(const char* name, const char* filepath, const QoreHashNode* opts, ExceptionSink* xsink) {
    if (!checkOpen(xsink, true)) {
        return;
    }

    struct stat st;
    if (stat(filepath, &st) != 0) {
        xsink->raiseException("TAR-ERROR", "failed to stat file '%s': %s", filepath, strerror(errno));
        return;
    }

    ArchiveEntryGuard entry(archive_entry_new());
    if (!entry) {
        xsink->raiseException("TAR-ERROR", "failed to create archive entry");
        return;
    }

    archive_entry_set_pathname(entry.get(), name);
    archive_entry_copy_stat(entry.get(), &st);

    int r = archive_write_header(write_archive, entry.get());
    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to write entry header: %s",
                              get_archive_error(write_archive));
        return;
    }

    // Read and write file data
    if (S_ISREG(st.st_mode) && st.st_size > 0) {
        FileHandle fp(fopen(filepath, "rb"));
        if (!fp) {
            xsink->raiseException("TAR-ERROR", "failed to open file '%s': %s", filepath, strerror(errno));
            return;
        }

        char buffer[TAR_BUFFER_SIZE];
        size_t bytes_read;
        while ((bytes_read = fread(buffer, 1, sizeof(buffer), fp.get())) > 0) {
            if (archive_write_data(write_archive, buffer, bytes_read) < 0) {
                xsink->raiseException("TAR-ERROR", "failed to write file data: %s",
                                      get_archive_error(write_archive));
                return;
            }
        }
    }
}

// Add directory entry
void QoreTarFile::addDirectory(const char* name, const QoreHashNode* opts, ExceptionSink* xsink) {
    if (!checkOpen(xsink, true)) {
        return;
    }

    struct archive_entry* entry = archive_entry_new();
    if (!entry) {
        xsink->raiseException("TAR-ERROR", "failed to create archive entry");
        return;
    }

    // Ensure name ends with /
    std::string dirname = name;
    if (!dirname.empty() && dirname.back() != '/') {
        dirname += '/';
    }

    archive_entry_set_pathname(entry, dirname.c_str());
    archive_entry_set_filetype(entry, AE_IFDIR);
    archive_entry_set_perm(entry, 0755);
    archive_entry_set_mtime(entry, time(nullptr), 0);

    int r = archive_write_header(write_archive, entry);
    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to write directory entry: %s",
                              get_archive_error(write_archive));
    }

    archive_entry_free(entry);
}

// Add symlink entry
void QoreTarFile::addSymlink(const char* name, const char* target, const QoreHashNode* opts, ExceptionSink* xsink) {
    if (!checkOpen(xsink, true)) {
        return;
    }

    struct archive_entry* entry = archive_entry_new();
    if (!entry) {
        xsink->raiseException("TAR-ERROR", "failed to create archive entry");
        return;
    }

    archive_entry_set_pathname(entry, name);
    archive_entry_set_filetype(entry, AE_IFLNK);
    archive_entry_set_symlink(entry, target);
    archive_entry_set_perm(entry, 0777);
    archive_entry_set_mtime(entry, time(nullptr), 0);

    int r = archive_write_header(write_archive, entry);
    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to write symlink entry: %s",
                              get_archive_error(write_archive));
    }

    archive_entry_free(entry);
}

// Add hardlink entry
void QoreTarFile::addHardlink(const char* name, const char* target, const QoreHashNode* opts, ExceptionSink* xsink) {
    if (!checkOpen(xsink, true)) {
        return;
    }

    struct archive_entry* entry = archive_entry_new();
    if (!entry) {
        xsink->raiseException("TAR-ERROR", "failed to create archive entry");
        return;
    }

    archive_entry_set_pathname(entry, name);
    archive_entry_set_hardlink(entry, target);
    archive_entry_set_mtime(entry, time(nullptr), 0);

    int r = archive_write_header(write_archive, entry);
    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to write hardlink entry: %s",
                              get_archive_error(write_archive));
    }

    archive_entry_free(entry);
}

// Extract all entries
void QoreTarFile::extractAll(const char* destPath, const QoreHashNode* opts, ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return;
    }

    std::string destination = destPath ? destPath : ".";
    bool preserve_permissions = true;
    bool preserve_ownership = false;
    bool preserve_times = true;
    bool overwrite = true;
    bool create_directories = true;
    int strip_count = 0;

    if (opts) {
        parseExtractOptions(opts, destination, preserve_permissions, preserve_ownership,
                            preserve_times, overwrite, create_directories, strip_count, xsink);
        if (*xsink) {
            return;
        }
    }

    reopenRead(xsink);
    if (*xsink) {
        return;
    }

    // Set up disk writer
    struct archive* disk = archive_write_disk_new();
    if (!disk) {
        xsink->raiseException("TAR-ERROR", "failed to create disk writer");
        return;
    }

    int flags = ARCHIVE_EXTRACT_TIME;
    if (preserve_permissions) {
        flags |= ARCHIVE_EXTRACT_PERM;
    }
    if (preserve_ownership) {
        flags |= ARCHIVE_EXTRACT_OWNER;
    }
    if (!overwrite) {
        flags |= ARCHIVE_EXTRACT_NO_OVERWRITE;
    }

    archive_write_disk_set_options(disk, flags);
    archive_write_disk_set_standard_lookup(disk);

    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        // Build destination path
        const char* entry_name = archive_entry_pathname(entry);

        // Security check: prevent path traversal attacks
        if (!isPathSafe(entry_name)) {
            xsink->raiseException("TAR-SECURITY-ERROR",
                "refusing to extract entry with unsafe path: '%s' (potential path traversal attack)",
                entry_name);
            break;
        }

        std::string dest_path = destination + "/" + entry_name;
        archive_entry_set_pathname(entry, dest_path.c_str());

        // Update hardlink target path if this is a hardlink
        const char* hardlink_target = archive_entry_hardlink(entry);
        if (hardlink_target && *hardlink_target) {
            // Also check hardlink target for path traversal
            if (!isPathSafe(hardlink_target)) {
                xsink->raiseException("TAR-SECURITY-ERROR",
                    "refusing to extract hardlink with unsafe target: '%s'",
                    hardlink_target);
                break;
            }
            std::string dest_link = destination + "/" + hardlink_target;
            archive_entry_set_hardlink(entry, dest_link.c_str());
        }

        // Also check symlink targets
        const char* symlink_target = archive_entry_symlink(entry);
        if (symlink_target && *symlink_target) {
            if (!isPathSafe(symlink_target)) {
                xsink->raiseException("TAR-SECURITY-ERROR",
                    "refusing to extract symlink with unsafe target: '%s'",
                    symlink_target);
                break;
            }
        }

        int r = archive_write_header(disk, entry);
        if (r != ARCHIVE_OK) {
            xsink->raiseException("TAR-ERROR", "failed to extract '%s': %s",
                                  entry_name, get_archive_error(disk));
            break;
        }

        // Copy data
        if (archive_entry_size(entry) > 0) {
            const void* buffer;
            size_t size;
            la_int64_t offset;

            while (archive_read_data_block(read_archive, &buffer, &size, &offset) == ARCHIVE_OK) {
                if (archive_write_data_block(disk, buffer, size, offset) != ARCHIVE_OK) {
                    xsink->raiseException("TAR-ERROR", "failed to write data for '%s': %s",
                                          entry_name, get_archive_error(disk));
                    break;
                }
            }
        }

        archive_write_finish_entry(disk);
    }

    archive_write_close(disk);
    archive_write_free(disk);
}

// Extract single entry
void QoreTarFile::extractEntry(const char* name, const char* destPath, ExceptionSink* xsink) {
    extractTo(name, destPath, xsink);
}

// Extract entry to destination
void QoreTarFile::extractTo(const char* name, const char* destination, ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return;
    }

    reopenRead(xsink);
    if (*xsink) {
        return;
    }

    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        if (entryNameEquals(archive_entry_pathname(entry), name)) {
            // Found the entry, write to file
            FILE* fp = fopen(destination, "wb");
            if (!fp) {
                xsink->raiseException("TAR-ERROR", "failed to open destination file '%s': %s",
                                      destination, strerror(errno));
                return;
            }

            char buffer[TAR_BUFFER_SIZE];
            la_ssize_t bytes_read;
            while ((bytes_read = archive_read_data(read_archive, buffer, sizeof(buffer))) > 0) {
                if (fwrite(buffer, 1, bytes_read, fp) != (size_t)bytes_read) {
                    xsink->raiseException("TAR-ERROR", "failed to write to destination file");
                    fclose(fp);
                    return;
                }
            }

            fclose(fp);
            return;
        }
        archive_read_data_skip(read_archive);
    }

    xsink->raiseException("TAR-ERROR", "entry '%s' not found", name);
}

// Get archive path
QoreStringNode* QoreTarFile::getPath() const {
    if (filepath.empty()) {
        return nullptr;
    }
    return new QoreStringNode(filepath);
}

// Parse add options
void QoreTarFile::parseAddOptions(const QoreHashNode* opts, int& mode, int& uid, int& gid,
                                  std::string& uname, std::string& gname, int64& modified_time,
                                  bool& preserve_permissions, bool& dereference_symlinks,
                                  ExceptionSink* xsink) const {
    if (!opts) {
        return;
    }

    QoreValue v = opts->getKeyValue("mode");
    if (!v.isNothing()) {
        mode = (int)v.getAsBigInt();
    }

    v = opts->getKeyValue("uid");
    if (!v.isNothing()) {
        uid = (int)v.getAsBigInt();
    }

    v = opts->getKeyValue("gid");
    if (!v.isNothing()) {
        gid = (int)v.getAsBigInt();
    }

    v = opts->getKeyValue("uname");
    if (v.getType() == NT_STRING) {
        uname = v.get<const QoreStringNode>()->c_str();
    }

    v = opts->getKeyValue("gname");
    if (v.getType() == NT_STRING) {
        gname = v.get<const QoreStringNode>()->c_str();
    }

    v = opts->getKeyValue("modified");
    if (v.getType() == NT_DATE) {
        modified_time = v.get<const DateTimeNode>()->getEpochSecondsUTC();
    }

    v = opts->getKeyValue("preserve_permissions");
    if (!v.isNothing()) {
        preserve_permissions = v.getAsBool();
    }

    v = opts->getKeyValue("dereference_symlinks");
    if (!v.isNothing()) {
        dereference_symlinks = v.getAsBool();
    }
}

// Parse extract options
void QoreTarFile::parseExtractOptions(const QoreHashNode* opts, std::string& destination,
                                       bool& preserve_permissions, bool& preserve_ownership,
                                       bool& preserve_times, bool& overwrite, bool& create_directories,
                                       int& strip_count, ExceptionSink* xsink) const {
    if (!opts) {
        return;
    }

    QoreValue v = opts->getKeyValue("destination");
    if (v.getType() == NT_STRING) {
        destination = v.get<const QoreStringNode>()->c_str();
    }

    v = opts->getKeyValue("preserve_permissions");
    if (!v.isNothing()) {
        preserve_permissions = v.getAsBool();
    }

    v = opts->getKeyValue("preserve_ownership");
    if (!v.isNothing()) {
        preserve_ownership = v.getAsBool();
    }

    v = opts->getKeyValue("preserve_times");
    if (!v.isNothing()) {
        preserve_times = v.getAsBool();
    }

    v = opts->getKeyValue("overwrite");
    if (!v.isNothing()) {
        overwrite = v.getAsBool();
    }

    v = opts->getKeyValue("create_directories");
    if (!v.isNothing()) {
        create_directories = v.getAsBool();
    }

    v = opts->getKeyValue("strip_count");
    if (!v.isNothing()) {
        strip_count = (int)v.getAsBigInt();
    }
}

// Open an input stream for reading an entry
QoreObject* QoreTarFile::openInputStream(const char* name, ExceptionSink* xsink) {
    if (!checkOpen(xsink, false)) {
        return nullptr;
    }

    reopenRead(xsink);
    if (*xsink) {
        return nullptr;
    }

    struct archive_entry* entry;
    while (archive_read_next_header(read_archive, &entry) == ARCHIVE_OK) {
        if (entryNameEquals(archive_entry_pathname(entry), name)) {
            TarInputStream* is = new TarInputStream(read_archive, entry, xsink);
            if (*xsink) {
                delete is;
                return nullptr;
            }
            return new QoreObject(QC_TARINPUTSTREAM, getProgram(), is);
        }
        archive_read_data_skip(read_archive);
    }

    xsink->raiseException("TAR-ERROR", "entry '%s' not found", name);
    return nullptr;
}

// Open an output stream for writing an entry
QoreObject* QoreTarFile::openOutputStream(const char* name, const QoreHashNode* opts, ExceptionSink* xsink) {
    if (!checkOpen(xsink, true)) {
        return nullptr;
    }

    int mode_val = 0644;
    int uid = 0, gid = 0;
    std::string uname, gname;
    int64 modified_time = 0;
    bool preserve_permissions = true;
    bool dereference_symlinks = false;

    if (opts) {
        parseAddOptions(opts, mode_val, uid, gid, uname, gname, modified_time,
                        preserve_permissions, dereference_symlinks, xsink);
        if (*xsink) {
            return nullptr;
        }
    }

    TarOutputStream* os = new TarOutputStream(write_archive, name, mode_val, xsink);
    if (*xsink) {
        delete os;
        return nullptr;
    }
    return new QoreObject(QC_TAROUTPUTSTREAM, getProgram(), os);
}

// Memory read callback for libarchive
la_ssize_t QoreTarFile::memory_read_callback(struct archive*, void* client_data, const void** buffer) {
    QoreTarFile* self = static_cast<QoreTarFile*>(client_data);

    if (self->memory_pos >= self->memory_buffer.size()) {
        *buffer = nullptr;
        return 0;
    }

    size_t remaining = self->memory_buffer.size() - self->memory_pos;
    size_t to_read = std::min(remaining, (size_t)TAR_BUFFER_SIZE);

    *buffer = self->memory_buffer.data() + self->memory_pos;
    self->memory_pos += to_read;

    return to_read;
}

// Memory close callback
int QoreTarFile::memory_close_callback(struct archive*, void* client_data) {
    return ARCHIVE_OK;
}

// Memory write callback
la_ssize_t QoreTarFile::memory_write_callback(struct archive*, void* client_data, const void* buffer, size_t length) {
    QoreTarFile* self = static_cast<QoreTarFile*>(client_data);

    size_t old_size = self->memory_buffer.size();
    self->memory_buffer.resize(old_size + length);
    memcpy(self->memory_buffer.data() + old_size, buffer, length);

    return length;
}

// Stream read callback
la_ssize_t QoreTarFile::stream_read_callback(struct archive*, void* client_data, const void** buffer) {
    QoreTarFile* self = static_cast<QoreTarFile*>(client_data);
    // Lazy allocation: only allocate buffer when first used by this thread
    static thread_local std::unique_ptr<char[]> read_buffer;
    if (!read_buffer) {
        read_buffer.reset(new char[TAR_BUFFER_SIZE]);
    }

    if (!self->input_stream) {
        return 0;
    }

    ExceptionSink xsink;
    int64 bytes_read = self->input_stream->read(read_buffer.get(), TAR_BUFFER_SIZE, &xsink);
    if (xsink) {
        return ARCHIVE_FATAL;
    }

    *buffer = read_buffer.get();
    return bytes_read;
}

// Stream write callback
la_ssize_t QoreTarFile::stream_write_callback(struct archive*, void* client_data, const void* buffer, size_t length) {
    QoreTarFile* self = static_cast<QoreTarFile*>(client_data);

    if (!self->output_stream) {
        return ARCHIVE_FATAL;
    }

    ExceptionSink xsink;
    self->output_stream->write(buffer, length, &xsink);
    if (xsink) {
        return ARCHIVE_FATAL;
    }

    return length;
}

// Stream close callback
int QoreTarFile::stream_close_callback(struct archive*, void* client_data) {
    return ARCHIVE_OK;
}

// QoreTarEntry implementation
QoreTarEntry::QoreTarEntry(const std::string& name, int64 size, int64 modified, int64 accessed,
                           int64 created, int mode, int uid, int gid, const std::string& uname,
                           const std::string& gname, const std::string& type, const std::string& link_target,
                           int devmajor, int devminor)
    : name(name), size(size), modified(modified), accessed(accessed), created(created),
      mode(mode), uid(uid), gid(gid), uname(uname), gname(gname), type(type),
      link_target(link_target), devmajor(devmajor), devminor(devminor) {
}

QoreTarEntry::~QoreTarEntry() {
}

QoreStringNode* QoreTarEntry::getName() const {
    return new QoreStringNode(name);
}

DateTimeNode* QoreTarEntry::getModified() const {
    return DateTimeNode::makeAbsolute(currentTZ(), modified);
}

DateTimeNode* QoreTarEntry::getAccessed() const {
    if (accessed <= 0) {
        return nullptr;
    }
    return DateTimeNode::makeAbsolute(currentTZ(), accessed);
}

DateTimeNode* QoreTarEntry::getCreated() const {
    if (created <= 0) {
        return nullptr;
    }
    return DateTimeNode::makeAbsolute(currentTZ(), created);
}

QoreStringNode* QoreTarEntry::getUname() const {
    if (uname.empty()) {
        return nullptr;
    }
    return new QoreStringNode(uname);
}

QoreStringNode* QoreTarEntry::getGname() const {
    if (gname.empty()) {
        return nullptr;
    }
    return new QoreStringNode(gname);
}

QoreStringNode* QoreTarEntry::getType() const {
    return new QoreStringNode(type);
}

QoreStringNode* QoreTarEntry::getLinkTarget() const {
    if (link_target.empty()) {
        return nullptr;
    }
    return new QoreStringNode(link_target);
}
