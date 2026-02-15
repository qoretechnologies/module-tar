# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarDecompressDataDataProvider class definition

/** TarDecompressDataDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Decompress TAR data provider
public class TarDecompressDataDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "decompress",
            "desc": "Decompress a TAR archive and return file contents",
            "type": "TarDecompressDataDataProvider",
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
        return new TarDecompressDataRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarDecompressDataResponseDataType();
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
            throw "TAR-ERROR", "one of 'archive_data', 'archive_path', or 'archive_location' must be provided";
        }

        @debug {
            printf("TarDecompressData: archive_size=%d\n", archive_data.size());
        }

        TarFile tar(archive_data);

        list<hash<TarEntryInfo>> entries = tar.entries();
        hash<string, auto> files = {};

        foreach hash<TarEntryInfo> entry in (entries) {
            if (!entry.is_directory && !entry.is_symlink && !entry.is_hardlink) {
                binary content = tar.read(entry.name);
                files{entry.name} = {
                    "content": content,
                    "size": content.size(),
                    "type": entry.type,
                };
            }
        }

        tar.close();

        return {
            "files": files,
            "entry_count": entries.size(),
            "file_count": files.size(),
        };
    }
}

#! Request type for decompress data operation
public class TarDecompressDataRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "TAR archive binary data",
                "desc": "The tar archive as binary data to decompress",
            },
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive (alternative to archive_data)",
                "example_value": "/path/to/archive.tar.gz",
            },
            "archive_location": {
                "type": StringOrNothingType,
                "display_name": "Archive Location",
                "short_desc": "Archive location URL",
                "desc": "A FileLocationHandler location URL for the tar archive (alternative to archive_data or archive_path)",
                "example_value": "file:///path/to/archive.tar.gz",
            },
        };
    }

    constructor() : HashDataType("TarDecompressDataRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("archive_data", "archive_path", "archive_location"),));
    }
}

#! Response type for decompress data operation
public class TarDecompressDataResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "files": {
                "type": AutoHashType,
                "display_name": "Files",
                "short_desc": "Extracted file contents",
                "desc": "Hash mapping entry names to their content and metadata",
            },
            "entry_count": {
                "type": IntType,
                "display_name": "Entry Count",
                "short_desc": "Total entries",
                "desc": "Total number of entries in the archive",
            },
            "file_count": {
                "type": IntType,
                "display_name": "File Count",
                "short_desc": "Files extracted",
                "desc": "Number of regular files extracted",
            },
        };
    }

    constructor() : HashDataType("TarDecompressDataResponse") {
        addQoreFields(Fields);
    }
}
}
