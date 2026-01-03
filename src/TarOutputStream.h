/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file TarOutputStream.h TarOutputStream class header */
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

#ifndef _QORE_TAR_TAROUTPUTSTREAM_H
#define _QORE_TAR_TAROUTPUTSTREAM_H

#include "tar-module.h"
#include <vector>
#include <string>

//! TarOutputStream - OutputStream implementation for writing tar entries
class TarOutputStream : public OutputStream {
public:
    DLLLOCAL TarOutputStream(struct archive* a, const char* entry_name, int mode, ExceptionSink* xsink);
    DLLLOCAL virtual ~TarOutputStream();

    DLLLOCAL virtual const char* getName() override { return "TarOutputStream"; }
    DLLLOCAL virtual bool isClosed() override { return closed; }
    DLLLOCAL virtual void close(ExceptionSink* xsink) override;
    DLLLOCAL virtual void write(const void* ptr, int64 count, ExceptionSink* xsink) override;

private:
    struct archive* archive;
    std::string entry_name;
    int mode;
    std::vector<char> buffer;  // Buffer data until close
    bool closed;
    bool header_written;
};

#endif // _QORE_TAR_TAROUTPUTSTREAM_H
