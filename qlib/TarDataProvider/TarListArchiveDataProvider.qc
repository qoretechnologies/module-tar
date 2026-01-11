# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarListArchiveDataProvider class definition

/** TarListArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! List archive contents data provider
public class TarListArchiveDataProvider inherits DataProvider::AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "list",
            "desc": "List contents of a TAR archive",
            "type": "TarListArchiveDataProvider",
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
        return new TarListRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarListResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        string archive_path;
        *binary archive_data;

        if (req.archive_path) {
            archive_path = req.archive_path;
        }
        if (req.archive_data) {
            archive_data = req.archive_data;
        }

        TarFile tar;
        if (archive_data) {
            tar = new TarFile(archive_data);
        } else if (archive_path) {
            tar = new TarFile(archive_path, "r");
        } else {
            throw "TAR-ERROR", "Either archive_path or archive_data must be provided";
        }

        list<hash<TarEntryInfo>> entries = tar.entries();
        tar.close();

        return {
            "entries": entries,
            "count": entries.size(),
        };
    }
}

#! Request type for list operation
public class TarListRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive file",
                "desc": "The filesystem path to the tar archive to list",
                "example_value": "/path/to/archive.tar.gz",
            },
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "Binary archive data",
                "desc": "The tar archive as binary data (alternative to archive_path)",
            },
        };
    }

    constructor() : HashDataType("TarListRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for list operation
public class TarListResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "entries": {
                "type": new ListDataType("EntryList", AutoType, True),
                "display_name": "Entries",
                "short_desc": "List of archive entries",
                "desc": "List of entries with metadata (name, size, type, etc.)",
            },
            "count": {
                "type": IntType,
                "display_name": "Entry Count",
                "short_desc": "Number of entries in archive",
                "desc": "Total number of entries in the archive",
            },
        };
    }

    constructor() : HashDataType("TarListResponse") {
        addQoreFields(Fields);
    }
}
}
