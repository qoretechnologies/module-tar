/* -*- mode: c++; indent-tabs-mode: nil -*- */
/** @file QoreTarFile.h QoreTarFile class header */
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

#ifndef _QORE_TAR_QORETARFILE_H
#define _QORE_TAR_QORETARFILE_H

#include "tar-module.h"

#include <string>
#include <vector>

//! QoreTarFile - private data class for TarFile Qore class
class QoreTarFile : public AbstractPrivateData {
public:
    //! Constructor for file-based archive
    DLLLOCAL QoreTarFile(const char* path, TarMode mode, int compression_method, int format, ExceptionSink* xsink);

    //! Constructor for in-memory archive (from binary data)
    DLLLOCAL QoreTarFile(const BinaryNode* data, ExceptionSink* xsink);

    //! Constructor for new in-memory archive
    DLLLOCAL QoreTarFile(int compression_method, int format, ExceptionSink* xsink);

    //! Constructor for stream-based reading
    DLLLOCAL QoreTarFile(InputStream* input, ExceptionSink* xsink);

    //! Constructor for stream-based writing
    DLLLOCAL QoreTarFile(OutputStream* output, int compression_method, int format, ExceptionSink* xsink);

    //! Destructor
    DLLLOCAL virtual ~QoreTarFile();

    //! Close the archive
    DLLLOCAL void close(ExceptionSink* xsink);

    //! Get archive as binary data (for in-memory archives)
    DLLLOCAL BinaryNode* toData(ExceptionSink* xsink);

    //! Get list of all entries
    DLLLOCAL QoreListNode* entries(ExceptionSink* xsink);

    //! Get number of entries
    DLLLOCAL int64 count(ExceptionSink* xsink);

    //! Check if entry exists
    DLLLOCAL bool hasEntry(const char* name, ExceptionSink* xsink);

    //! Read entry as binary data
    DLLLOCAL BinaryNode* read(const char* name, ExceptionSink* xsink);

    //! Read entry as text
    DLLLOCAL QoreStringNode* readText(const char* name, const char* encoding, ExceptionSink* xsink);

    //! Get entry info
    DLLLOCAL QoreHashNode* getEntry(const char* name, ExceptionSink* xsink);

    //! Add binary data as entry
    DLLLOCAL void add(const char* name, const BinaryNode* data, const QoreHashNode* opts, ExceptionSink* xsink);

    //! Add text as entry
    DLLLOCAL void addText(const char* name, const QoreStringNode* text, const char* encoding,
                          const QoreHashNode* opts, ExceptionSink* xsink);

    //! Add file from filesystem
    DLLLOCAL void addFile(const char* name, const char* filepath, const QoreHashNode* opts, ExceptionSink* xsink);

    //! Add directory entry
    DLLLOCAL void addDirectory(const char* name, const QoreHashNode* opts, ExceptionSink* xsink);

    //! Add symlink entry
    DLLLOCAL void addSymlink(const char* name, const char* target, const QoreHashNode* opts, ExceptionSink* xsink);

    //! Add hardlink entry
    DLLLOCAL void addHardlink(const char* name, const char* target, const QoreHashNode* opts, ExceptionSink* xsink);

    //! Extract all entries to directory
    DLLLOCAL void extractAll(const char* destPath, const QoreHashNode* opts, ExceptionSink* xsink);

    //! Extract single entry
    DLLLOCAL void extractEntry(const char* name, const char* destPath, ExceptionSink* xsink);

    //! Extract entry to specific destination
    DLLLOCAL void extractTo(const char* name, const char* destination, ExceptionSink* xsink);

    //! Get archive path
    DLLLOCAL QoreStringNode* getPath() const;

    //! Get compression method
    DLLLOCAL int getCompressionMethod() const { return compression_method; }

    //! Get archive format
    DLLLOCAL int getFormat() const { return format; }

    //! Open an input stream for reading an entry
    DLLLOCAL QoreObject* openInputStream(const char* name, ExceptionSink* xsink);

    //! Open an output stream for writing an entry
    DLLLOCAL QoreObject* openOutputStream(const char* name, const QoreHashNode* opts, ExceptionSink* xsink);

    //! Get reader handle (for stream classes)
    DLLLOCAL struct archive* getReadArchive() const { return read_archive; }

    //! Get writer handle (for stream classes)
    DLLLOCAL struct archive* getWriteArchive() const { return write_archive; }

private:
    std::string filepath;
    TarMode mode;
    struct archive* read_archive;
    struct archive* write_archive;
    int compression_method;
    int compression_level;  // -1 = default, 1-9 for gzip/bzip2/xz
    int format;
    bool in_memory;
    bool closed;

    // For in-memory archives
    std::vector<char> memory_buffer;
    size_t memory_pos;

    // For stream-based archives
    InputStream* input_stream;
    OutputStream* output_stream;

    //! Create TarEntryInfo hash from archive_entry
    DLLLOCAL QoreHashNode* createEntryInfo(struct archive_entry* entry, ExceptionSink* xsink) const;

    //! Parse add options
    DLLLOCAL void parseAddOptions(const QoreHashNode* opts, int& mode, int& uid, int& gid,
                                  std::string& uname, std::string& gname, int64& modified_time,
                                  bool& preserve_permissions, bool& dereference_symlinks,
                                  ExceptionSink* xsink) const;

    //! Parse extract options
    DLLLOCAL void parseExtractOptions(const QoreHashNode* opts, std::string& destination,
                                       bool& preserve_permissions, bool& preserve_ownership,
                                       bool& preserve_times, bool& overwrite, bool& create_directories,
                                       int& strip_count, ExceptionSink* xsink) const;

    //! Check archive is open and in correct mode
    DLLLOCAL bool checkOpen(ExceptionSink* xsink, bool forWrite = false);

    //! Open for reading (file or memory)
    DLLLOCAL void openRead(ExceptionSink* xsink);

    //! Open for writing (file or memory)
    DLLLOCAL void openWrite(ExceptionSink* xsink);

    //! Open for appending (reads existing, prepares for writing)
    DLLLOCAL void openAppend(ExceptionSink* xsink);

    //! Copy entries from read archive to write archive
    DLLLOCAL void copyEntries(ExceptionSink* xsink);

    //! Reopen archive for reading from beginning
    DLLLOCAL void reopenRead(ExceptionSink* xsink);

    //! Setup compression filter for writing
    DLLLOCAL void setupCompressionFilter(ExceptionSink* xsink);

    //! libarchive callbacks for memory operations
    static la_ssize_t memory_read_callback(struct archive*, void* client_data, const void** buffer);
    static int memory_close_callback(struct archive*, void* client_data);
    static la_ssize_t memory_write_callback(struct archive*, void* client_data, const void* buffer, size_t length);

    //! libarchive callbacks for stream operations
    static la_ssize_t stream_read_callback(struct archive*, void* client_data, const void** buffer);
    static la_ssize_t stream_write_callback(struct archive*, void* client_data, const void* buffer, size_t length);
    static int stream_close_callback(struct archive*, void* client_data);
};

//! QoreTarEntry - private data class for TarEntry Qore class
class QoreTarEntry : public AbstractPrivateData {
public:
    DLLLOCAL QoreTarEntry(const std::string& name, int64 size, int64 modified, int64 accessed,
                          int64 created, int mode, int uid, int gid, const std::string& uname,
                          const std::string& gname, const std::string& type, const std::string& link_target,
                          int devmajor, int devminor);

    DLLLOCAL virtual ~QoreTarEntry();

    DLLLOCAL QoreStringNode* getName() const;
    DLLLOCAL int64 getSize() const { return size; }
    DLLLOCAL DateTimeNode* getModified() const;
    DLLLOCAL DateTimeNode* getAccessed() const;
    DLLLOCAL DateTimeNode* getCreated() const;
    DLLLOCAL int getMode() const { return mode; }
    DLLLOCAL int getUid() const { return uid; }
    DLLLOCAL int getGid() const { return gid; }
    DLLLOCAL QoreStringNode* getUname() const;
    DLLLOCAL QoreStringNode* getGname() const;
    DLLLOCAL QoreStringNode* getType() const;
    DLLLOCAL QoreStringNode* getLinkTarget() const;
    DLLLOCAL bool isDirectory() const { return type == "directory"; }
    DLLLOCAL bool isSymlink() const { return type == "symlink"; }
    DLLLOCAL bool isHardlink() const { return type == "hardlink"; }
    DLLLOCAL int getDevmajor() const { return devmajor; }
    DLLLOCAL int getDevminor() const { return devminor; }

private:
    std::string name;
    int64 size;
    int64 modified;
    int64 accessed;
    int64 created;
    int mode;
    int uid;
    int gid;
    std::string uname;
    std::string gname;
    std::string type;
    std::string link_target;
    int devmajor;
    int devminor;
};

#endif // _QORE_TAR_QORETARFILE_H
