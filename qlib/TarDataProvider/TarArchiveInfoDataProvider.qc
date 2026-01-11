# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarArchiveInfoDataProvider class definition

/** TarArchiveInfoDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Archive info data provider
public class TarArchiveInfoDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "info",
            "desc": "Get metadata about a TAR archive",
            "type": "TarArchiveInfoDataProvider",
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
        return new TarArchiveInfoRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarArchiveInfoResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        TarFile tar;
        if (req.archive_data) {
            tar = new TarFile(req.archive_data);
        } else if (req.archive_path) {
            tar = new TarFile(req.archive_path, "r");
        } else {
            throw "TAR-ERROR", "Either archive_path or archive_data must be provided";
        }

        list<hash<TarEntryInfo>> entries = tar.entries();

        int total_size = 0;
        int file_count = 0;
        int dir_count = 0;
        int link_count = 0;

        foreach hash<TarEntryInfo> entry in (entries) {
            total_size += entry.size;
            if (entry.is_directory) {
                dir_count++;
            } else if (entry.is_symlink || entry.is_hardlink) {
                link_count++;
            } else {
                file_count++;
            }
        }

        tar.close();

        return {
            "entry_count": entries.size(),
            "file_count": file_count,
            "directory_count": dir_count,
            "link_count": link_count,
            "total_uncompressed_size": total_size,
        };
    }
}

#! Request type for archive info operation
public class TarArchiveInfoRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive",
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

    constructor() : HashDataType("TarArchiveInfoRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for archive info operation
public class TarArchiveInfoResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "entry_count": {
                "type": IntType,
                "display_name": "Entry Count",
                "short_desc": "Total number of entries",
                "desc": "Total number of entries in the archive",
            },
            "file_count": {
                "type": IntType,
                "display_name": "File Count",
                "short_desc": "Number of regular files",
                "desc": "Number of regular file entries",
            },
            "directory_count": {
                "type": IntType,
                "display_name": "Directory Count",
                "short_desc": "Number of directories",
                "desc": "Number of directory entries",
            },
            "link_count": {
                "type": IntType,
                "display_name": "Link Count",
                "short_desc": "Number of links",
                "desc": "Number of symlink and hardlink entries",
            },
            "total_uncompressed_size": {
                "type": IntType,
                "display_name": "Total Size",
                "short_desc": "Total uncompressed size",
                "desc": "Total uncompressed size of all entries in bytes",
            },
        };
    }

    constructor() : HashDataType("TarArchiveInfoResponse") {
        addQoreFields(Fields);
    }
}
}
