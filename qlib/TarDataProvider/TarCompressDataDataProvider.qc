# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarCompressDataDataProvider class definition

/** TarCompressDataDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Compress data to TAR data provider
public class TarCompressDataDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "compress",
            "desc": "Compress data into an in-memory TAR archive",
            "type": "TarCompressDataDataProvider",
            "supports_request": True,
        };
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
        return new TarCompressDataRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarCompressDataResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        int compression = getCompressionMethod(req.compression);
        int format = getTarFormat(req.format);

        hash<TarCreateOptions> create_opts = <TarCreateOptions>{
            "compression_method": compression,
            "format": format,
        };

        TarFile tar(create_opts);

        int entry_count = 0;
        if (req.files) {
            foreach hash<auto> file in (req.files) {
                string name = file.name;
                if (file.data) {
                    tar.add(name, file.data);
                } else if (file.text) {
                    tar.add(name, file.text);
                }
                entry_count++;
            }
        }

        binary archive_data = tar.toData();

        return {
            "archive_data": archive_data,
            "archive_size": archive_data.size(),
            "entry_count": entry_count,
        };
    }
}

#! Request type for compress data operation
public class TarCompressDataRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "compression": {
                "type": StringOrNothingType,
                "display_name": "Compression",
                "short_desc": "Compression method",
                "desc": "Compression method: none, gzip, bzip2, xz, zstd, or lz4",
                "example_value": "gzip",
            },
            "format": {
                "type": StringOrNothingType,
                "display_name": "Format",
                "short_desc": "TAR format",
                "desc": "The tar format: ustar, pax, gnu, or v7",
                "example_value": "pax",
            },
            "files": {
                "type": new ListDataType("CompressFileList", AutoHashType, True),
                "display_name": "Files",
                "short_desc": "Files to compress",
                "desc": "List of entries. Each entry should have 'name' and either 'data' (binary) or 'text' (string)",
                "example_value": ({"name": "hello.txt", "text": "Hello World"},),
            },
        };
    }

    constructor() : HashDataType("TarCompressDataRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for compress data operation
public class TarCompressDataResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryType,
                "display_name": "Archive Data",
                "short_desc": "Compressed archive data",
                "desc": "The compressed tar archive as binary data",
            },
            "archive_size": {
                "type": IntType,
                "display_name": "Archive Size",
                "short_desc": "Size in bytes",
                "desc": "Size of the compressed archive in bytes",
            },
            "entry_count": {
                "type": IntType,
                "display_name": "Entry Count",
                "short_desc": "Number of entries",
                "desc": "Number of entries in the archive",
            },
        };
    }

    constructor() : HashDataType("TarCompressDataResponse") {
        addQoreFields(Fields);
    }
}
}
