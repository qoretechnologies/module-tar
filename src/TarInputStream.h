/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file TarInputStream.h TarInputStream class header */
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

#ifndef _QORE_TAR_TARINPUTSTREAM_H
#define _QORE_TAR_TARINPUTSTREAM_H

#include "tar-module.h"

//! TarInputStream - InputStream implementation for reading tar entries
class TarInputStream : public InputStream {
public:
    DLLLOCAL TarInputStream(struct archive* a, struct archive_entry* entry, ExceptionSink* xsink);
    DLLLOCAL virtual ~TarInputStream();

    DLLLOCAL virtual const char* getName() override { return "TarInputStream"; }
    DLLLOCAL virtual int64 read(void* ptr, int64 limit, ExceptionSink* xsink) override;
    DLLLOCAL virtual int64 peek(ExceptionSink* xsink) override;
    DLLLOCAL bool isClosed() { return closed; }

    DLLLOCAL QoreHashNode* getEntryInfo(ExceptionSink* xsink);

private:
    struct archive* archive;
    struct archive_entry* entry;
    int64 entry_size;
    int64 bytes_read;
    bool closed;
    int peek_byte;
    bool has_peek;
};

#endif // _QORE_TAR_TARINPUTSTREAM_H
