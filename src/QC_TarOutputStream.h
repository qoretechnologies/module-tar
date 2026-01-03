/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file QC_TarOutputStream.h TarOutputStream class header */
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

#ifndef _QORE_TAR_QC_TAROUTPUTSTREAM_H
#define _QORE_TAR_QC_TAROUTPUTSTREAM_H

#include "tar-module.h"

// QoreClass pointer for TarOutputStream (for creating objects)
DLLLOCAL extern QoreClass* QC_TAROUTPUTSTREAM;

// Class ID for TarOutputStream
DLLLOCAL extern qore_classid_t CID_TAROUTPUTSTREAM;

// Initialize the TarOutputStream class
DLLLOCAL QoreClass* initTarOutputStreamClass(QoreNamespace& ns);

#endif // _QORE_TAR_QC_TAROUTPUTSTREAM_H
