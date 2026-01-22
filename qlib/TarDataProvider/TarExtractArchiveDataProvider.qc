# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarExtractArchiveDataProvider class definition

/** TarExtractArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Extract archive data provider
public class TarExtractArchiveDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "extract",
            "desc": "Extract all contents from a TAR archive",
            "type": "TarExtractArchiveDataProvider",
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
        return new TarExtractArchiveRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarExtractArchiveResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        @debug {
            printf("TarExtractArchive: archive=%y destination=%y overwrite=%y\n",
                req.archive_path ?? "(data)", req.destination ?? ".", req.overwrite ?? False);
        }

        TarFile tar;
        if (req.archive_data) {
            tar = new TarFile(req.archive_data);
        } else if (req.archive_path) {
            tar = new TarFile(req.archive_path, "r");
        } else {
            throw "TAR-ERROR", "Either archive_path or archive_data must be provided";
        }

        string destination = req.destination ?? ".";

        hash<TarExtractOptions> extract_opts = <TarExtractOptions>{
            "destination": destination,
            "preserve_permissions": req.preserve_permissions ?? True,
            "preserve_times": req.preserve_times ?? True,
            "overwrite": req.overwrite ?? False,
            "create_directories": True,
        };

        list<hash<TarEntryInfo>> entries = tar.entries();
        tar.extractAll(extract_opts);
        tar.close();

        @debug {
            printf("TarExtractArchive: extracted %d entries to %y\n", entries.size(), destination);
        }

        return {
            "destination": destination,
            "extracted_count": entries.size(),
            "entries": entries,
        };
    }
}

#! Request type for extract archive operation
public class TarExtractArchiveRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive to extract",
                "example_value": "/path/to/archive.tar.gz",
            },
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "Binary archive data",
                "desc": "The tar archive as binary data (alternative to archive_path)",
            },
            "destination": {
                "type": StringOrNothingType,
                "display_name": "Destination",
                "short_desc": "Extraction destination directory",
                "desc": "The directory where files will be extracted (default: current directory)",
                "example_value": "/tmp/extracted",
            },
            "preserve_permissions": {
                "type": SoftBoolType,
                "display_name": "Preserve Permissions",
                "short_desc": "Restore file permissions",
                "desc": "If true, restores original file permissions (default: true)",
                "example_value": True,
            },
            "preserve_times": {
                "type": SoftBoolType,
                "display_name": "Preserve Times",
                "short_desc": "Restore modification times",
                "desc": "If true, restores original modification times (default: true)",
                "example_value": True,
            },
            "overwrite": {
                "type": SoftBoolType,
                "display_name": "Overwrite",
                "short_desc": "Overwrite existing files",
                "desc": "If true, overwrites existing files (default: false)",
                "example_value": False,
            },
        };
    }

    constructor() : HashDataType("TarExtractArchiveRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for extract archive operation
public class TarExtractArchiveResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "destination": {
                "type": StringType,
                "display_name": "Destination",
                "short_desc": "Extraction directory",
                "desc": "The directory where files were extracted",
            },
            "extracted_count": {
                "type": IntType,
                "display_name": "Extracted Count",
                "short_desc": "Number of entries extracted",
                "desc": "Total number of entries that were extracted",
            },
            "entries": {
                "type": new ListDataType("ExtractedEntryList", AutoType, True),
                "display_name": "Entries",
                "short_desc": "List of extracted entries",
                "desc": "List of entries that were extracted with metadata",
            },
        };
    }

    constructor() : HashDataType("TarExtractArchiveResponse") {
        addQoreFields(Fields);
    }
}
}
