/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file TarOutputStream.cpp TarOutputStream class implementation */
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

#include "TarOutputStream.h"
#include <cstring>
#include <ctime>

TarOutputStream::TarOutputStream(struct archive* a, const char* entry_name, int mode, ExceptionSink* xsink)
    : archive(a), entry_name(entry_name), mode(mode), closed(false), header_written(false) {
}

TarOutputStream::~TarOutputStream() {
    if (!closed) {
        ExceptionSink xsink;
        close(&xsink);
    }
}

void TarOutputStream::write(const void* ptr, int64 count, ExceptionSink* xsink) {
    if (closed) {
        xsink->raiseException("STREAM-CLOSED-ERROR", "stream is closed");
        return;
    }

    if (count <= 0) {
        return;
    }

    // Buffer the data - we need to know total size before writing header
    size_t old_size = buffer.size();
    buffer.resize(old_size + count);
    memcpy(buffer.data() + old_size, ptr, count);
}

void TarOutputStream::close(ExceptionSink* xsink) {
    if (closed) {
        return;
    }

    closed = true;

    // Now write the entry with full data
    struct archive_entry* entry = archive_entry_new();
    if (!entry) {
        xsink->raiseException("TAR-ERROR", "failed to create archive entry");
        return;
    }

    archive_entry_set_pathname(entry, entry_name.c_str());
    archive_entry_set_size(entry, buffer.size());
    archive_entry_set_filetype(entry, AE_IFREG);
    archive_entry_set_perm(entry, mode);
    archive_entry_set_mtime(entry, time(nullptr), 0);

    int r = archive_write_header(archive, entry);
    if (r != ARCHIVE_OK) {
        xsink->raiseException("TAR-ERROR", "failed to write entry header: %s",
                              get_archive_error(archive));
        archive_entry_free(entry);
        return;
    }

    if (!buffer.empty()) {
        la_ssize_t written = archive_write_data(archive, buffer.data(), buffer.size());
        if (written < 0 || (size_t)written != buffer.size()) {
            xsink->raiseException("TAR-ERROR", "failed to write entry data: %s",
                                  get_archive_error(archive));
        }
    }

    archive_entry_free(entry);
    buffer.clear();
}
