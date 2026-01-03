/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file TarInputStream.cpp TarInputStream class implementation */
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

#include "TarInputStream.h"

TarInputStream::TarInputStream(struct archive* a, struct archive_entry* entry, ExceptionSink* xsink)
    : archive(a), entry(entry), bytes_read(0), closed(false), peek_byte(-1), has_peek(false) {
    entry_size = archive_entry_size(entry);
}

TarInputStream::~TarInputStream() {
    closed = true;
}

int64 TarInputStream::read(void* ptr, int64 limit, ExceptionSink* xsink) {
    if (closed) {
        xsink->raiseException("STREAM-CLOSED-ERROR", "stream is closed");
        return -1;
    }

    if (bytes_read >= entry_size) {
        return 0;  // EOF
    }

    char* buf = static_cast<char*>(ptr);
    int64 total_read = 0;

    // Return peeked byte first
    if (has_peek && limit > 0) {
        buf[0] = static_cast<char>(peek_byte);
        total_read = 1;
        has_peek = false;
        buf++;
        limit--;
    }

    if (limit > 0) {
        la_ssize_t r = archive_read_data(archive, buf, limit);
        if (r < 0) {
            xsink->raiseException("TAR-READ-ERROR", "failed to read data: %s",
                                  get_archive_error(archive));
            return -1;
        }
        total_read += r;
    }

    bytes_read += total_read;
    return total_read;
}

int64 TarInputStream::peek(ExceptionSink* xsink) {
    if (closed) {
        xsink->raiseException("STREAM-CLOSED-ERROR", "stream is closed");
        return -1;
    }

    if (has_peek) {
        return peek_byte;
    }

    if (bytes_read >= entry_size) {
        return -1;  // EOF
    }

    unsigned char buf;
    la_ssize_t r = archive_read_data(archive, &buf, 1);
    if (r < 0) {
        xsink->raiseException("TAR-READ-ERROR", "failed to peek data: %s",
                              get_archive_error(archive));
        return -1;
    }
    if (r == 0) {
        return -1;  // EOF
    }

    peek_byte = buf;
    has_peek = true;
    return peek_byte;
}

QoreHashNode* TarInputStream::getEntryInfo(ExceptionSink* xsink) {
    if (!entry) {
        return nullptr;
    }

    ReferenceHolder<QoreHashNode> info(new QoreHashNode(hashdeclTarEntryInfo, xsink), xsink);

    info->setKeyValue("name", new QoreStringNode(archive_entry_pathname(entry)), xsink);
    info->setKeyValue("size", entry_size, xsink);

    if (archive_entry_mtime_is_set(entry)) {
        info->setKeyValue("modified", DateTimeNode::makeAbsolute(currentTZ(), archive_entry_mtime(entry)), xsink);
    }

    info->setKeyValue("mode", archive_entry_mode(entry), xsink);

    int filetype = archive_entry_filetype(entry);
    const char* type_str;
    switch (filetype) {
        case AE_IFREG:  type_str = "file"; break;
        case AE_IFDIR:  type_str = "directory"; break;
        case AE_IFLNK:  type_str = "symlink"; break;
        default:        type_str = "unknown"; break;
    }
    info->setKeyValue("type", new QoreStringNode(type_str), xsink);
    info->setKeyValue("is_directory", filetype == AE_IFDIR, xsink);
    info->setKeyValue("is_symlink", filetype == AE_IFLNK, xsink);

    return info.release();
}
