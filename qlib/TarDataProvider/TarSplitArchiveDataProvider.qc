# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarSplitArchiveDataProvider class definition

/** TarSplitArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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

#! Contains all public definitions in the TarDataProvider module
public namespace TarDataProvider {
#! Split archive data provider
public class TarSplitArchiveDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "split",
            "desc": "Split a TAR archive into multiple fixed-size binary chunks for multi-volume "
                "storage or transfer",
            "type": "TarSplitArchiveDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarSplitArchiveResponseDataType ResponseType();
    }

    private {
        *hash<auto> opts;
    }

    constructor(*hash<auto> opts) {
        self.opts = opts;
    }

    string getName() {
        return ProviderInfo.name;
    }

    private hash<DataProviderInfo> getStaticInfoImpl() {
        return ProviderInfo;
    }

    private *AbstractDataProviderType getRequestTypeImpl() {
        return new TarSplitArchiveRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarSplitArchiveResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        *binary archive_data = req.archive_data;
        if (!archive_data && req.archive_location) {
            archive_data = FileLocationHandler::getBinaryFileFromLocation(req.archive_location);
        }
        if (!archive_data && req.archive_path) {
            archive_data = ReadOnlyFile::readBinaryFile(req.archive_path);
        }
        if (!archive_data) {
            throw "TAR-ERROR", "one of 'archive_data', 'archive_path', or 'archive_location' "
                "must be provided";
        }

        int chunk_size = req.chunk_size;
        if (chunk_size <= 0) {
            throw "TAR-ERROR", sprintf("chunk_size must be greater than 0; got %d", chunk_size);
        }

        int total_size = archive_data.size();
        list<binary> chunks = ();
        int offset = 0;
        while (offset < total_size) {
            int remaining = total_size - offset;
            int len = remaining < chunk_size ? remaining : chunk_size;
            chunks += archive_data.substr(offset, len);
            offset += len;
        }

        return {
            "chunks": chunks,
            "chunk_count": chunks.size(),
            "total_size": total_size,
        };
    }
}

#! Request type for split archive operation
public class TarSplitArchiveRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "TAR archive binary data",
                "desc": "The tar archive as binary data to split",
            },
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive (alternative to `archive_data`)",
                "example_value": "/path/to/archive.tar.gz",
            },
            "archive_location": {
                "type": StringOrNothingType,
                "display_name": "Archive Location",
                "short_desc": "Archive location URL",
                "desc": "A FileLocationHandler location URL for the tar archive "
                    "(alternative to `archive_data` or `archive_path`)",
                "example_value": "file:///path/to/archive.tar.gz",
            },
            "chunk_size": {
                "type": IntType,
                "display_name": "Chunk Size",
                "short_desc": "Maximum chunk size in bytes",
                "desc": "The maximum size in bytes for each chunk. The last chunk may be smaller "
                    "if the archive size is not evenly divisible",
                "example_value": 1048576,
            },
        };
    }

    constructor() : HashDataType("TarSplitArchiveRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("archive_data", "archive_path", "archive_location"),));
    }
}

#! Response type for split archive operation
public class TarSplitArchiveResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "chunks": {
                "type": new ListDataType("ChunkList", BinaryType, True),
                "display_name": "Chunks",
                "short_desc": "List of binary chunks",
                "desc": "The archive split into a list of binary chunks",
            },
            "chunk_count": {
                "type": IntType,
                "display_name": "Chunk Count",
                "short_desc": "Number of chunks",
                "desc": "The number of chunks the archive was split into",
            },
            "total_size": {
                "type": IntType,
                "display_name": "Total Size",
                "short_desc": "Original archive size in bytes",
                "desc": "The total size of the original archive in bytes",
            },
        };
    }

    constructor() : HashDataType("TarSplitArchiveResponse") {
        addQoreFields(Fields);
    }
}
}
