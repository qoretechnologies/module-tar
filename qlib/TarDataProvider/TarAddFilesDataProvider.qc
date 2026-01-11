# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarAddFilesDataProvider class definition

/** TarAddFilesDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Add files to archive data provider
public class TarAddFilesDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "add",
            "desc": "Add files to an existing TAR archive",
            "type": "TarAddFilesDataProvider",
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
        return new TarAddFilesRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarAddFilesResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        if (!req.archive_path) {
            throw "TAR-ERROR", "archive_path is required for add operation";
        }

        int compression = getCompressionMethod(req.compression);
        int format = getTarFormat(req.format);

        hash<TarCreateOptions> create_opts = <TarCreateOptions>{
            "compression_method": compression,
            "format": format,
        };

        TarFile tar(req.archive_path, "a", create_opts);

        int added_count = 0;

        if (req.files) {
            foreach hash<auto> file in (req.files) {
                string name = file.name;
                if (file.data) {
                    tar.add(name, file.data);
                } else if (file.text) {
                    tar.add(name, file.text);
                } else if (file.source_path) {
                    tar.addFile(name, file.source_path);
                }
                added_count++;
            }
        }

        tar.close();

        return {
            "archive_path": req.archive_path,
            "added_count": added_count,
        };
    }
}

#! Request type for add files operation
public class TarAddFilesRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive to modify",
                "example_value": "/path/to/archive.tar",
            },
            "compression": {
                "type": StringOrNothingType,
                "display_name": "Compression",
                "short_desc": "Compression for the archive",
                "desc": "Compression method if archive needs to be rewritten: none, gzip, bzip2, xz, zstd, or lz4",
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
                "type": new ListDataType("AddFileList", AutoHashType, True),
                "display_name": "Files",
                "short_desc": "Files to add",
                "desc": "List of file entries to add. Each entry should have 'name' and one of: 'data', 'text', or 'source_path'",
                "example_value": ({"name": "new.txt", "text": "New content"},),
            },
        };
    }

    constructor() : HashDataType("TarAddFilesRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for add files operation
public class TarAddFilesResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringType,
                "display_name": "Archive Path",
                "short_desc": "Path to modified archive",
                "desc": "The filesystem path to the modified archive",
            },
            "added_count": {
                "type": IntType,
                "display_name": "Added Count",
                "short_desc": "Number of files added",
                "desc": "Number of files that were added to the archive",
            },
        };
    }

    constructor() : HashDataType("TarAddFilesResponse") {
        addQoreFields(Fields);
    }
}
}
