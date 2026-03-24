# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarJoinArchiveDataProvider class definition

/** TarJoinArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Join archive data provider
public class TarJoinArchiveDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "join",
            "desc": "Join binary archive chunks back into a single TAR archive",
            "type": "TarJoinArchiveDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarJoinArchiveResponseDataType ResponseType();
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
        return new TarJoinArchiveRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarJoinArchiveResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        list<binary> chunks = req.chunks;
        if (!chunks || !chunks.size()) {
            throw "TAR-ERROR", "at least one chunk must be provided";
        }

        binary archive_data = binary();
        foreach binary chunk in (chunks) {
            archive_data += chunk;
        }

        return {
            "archive_data": archive_data,
            "total_size": archive_data.size(),
            "chunk_count": chunks.size(),
        };
    }
}

#! Request type for join archive operation
public class TarJoinArchiveRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "chunks": {
                "type": new ListDataType("JoinChunkList", BinaryType, True),
                "display_name": "Chunks",
                "short_desc": "Binary chunks to join",
                "desc": "A list of binary chunks to concatenate back into a single tar archive. "
                    "Chunks must be in the correct order as produced by the split operation",
            },
        };
    }

    constructor() : HashDataType("TarJoinArchiveRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for join archive operation
public class TarJoinArchiveResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryType,
                "display_name": "Archive Data",
                "short_desc": "Reassembled archive binary",
                "desc": "The reassembled tar archive as binary data",
            },
            "total_size": {
                "type": IntType,
                "display_name": "Total Size",
                "short_desc": "Archive size in bytes",
                "desc": "The total size of the reassembled archive in bytes",
            },
            "chunk_count": {
                "type": IntType,
                "display_name": "Chunk Count",
                "short_desc": "Number of chunks joined",
                "desc": "The number of chunks that were concatenated",
            },
        };
    }

    constructor() : HashDataType("TarJoinArchiveResponse") {
        addQoreFields(Fields);
    }
}
}
