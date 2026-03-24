# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarVerifyArchiveDataProvider class definition

/** TarVerifyArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Verify archive data provider
public class TarVerifyArchiveDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "verify",
            "desc": "Verify the integrity of a TAR archive by reading all entries and their data "
                "blocks without extracting to disk",
            "type": "TarVerifyArchiveDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarVerifyArchiveResponseDataType ResponseType();
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
        return new TarVerifyArchiveRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarVerifyArchiveResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        *binary archive_data = req.archive_data;
        if (!archive_data && req.archive_location) {
            archive_data = FileLocationHandler::getBinaryFileFromLocation(req.archive_location);
        }

        TarFile tar;
        if (archive_data) {
            tar = new TarFile(archive_data);
        } else if (req.archive_path) {
            tar = new TarFile(req.archive_path, "r");
        } else {
            throw "TAR-ERROR", "one of 'archive_path', 'archive_data', or 'archive_location' "
                "must be provided";
        }

        list<hash<TarEntryInfo>> entries = tar.entries();
        int total_size = 0;
        list<string> errors = ();

        foreach hash<TarEntryInfo> entry in (entries) {
            if (!entry.is_directory && !entry.is_symlink && !entry.is_hardlink) {
                try {
                    binary content = tar.read(entry.name);
                    total_size += content.size();
                    if (content.size() != entry.size) {
                        errors += sprintf("size mismatch for %y: expected %d, got %d",
                            entry.name, entry.size, content.size());
                    }
                } catch (hash<ExceptionInfo> ex) {
                    errors += sprintf("read error for %y: %s: %s",
                        entry.name, ex.err, ex.desc);
                }
            }
        }

        *int cm = tar.getCompressionMethod();
        *int fmt = tar.getFormat();
        tar.close();

        return {
            "entry_count": entries.size(),
            "total_size": total_size,
            "compression": get_compression_name(cm ?? 0),
            "format": get_format_name(fmt ?? 0),
            "valid": !errors.size(),
            "errors": errors,
        };
    }
}

#! Request type for verify archive operation
public class TarVerifyArchiveRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive to verify",
                "example_value": "/path/to/archive.tar.gz",
            },
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "TAR archive binary data",
                "desc": "The tar archive as binary data (alternative to `archive_path`)",
            },
            "archive_location": {
                "type": StringOrNothingType,
                "display_name": "Archive Location",
                "short_desc": "Archive location URL",
                "desc": "A FileLocationHandler location URL for the tar archive "
                    "(alternative to `archive_path` or `archive_data`)",
                "example_value": "file:///path/to/archive.tar.gz",
            },
        };
    }

    constructor() : HashDataType("TarVerifyArchiveRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("archive_path", "archive_data", "archive_location"),));
    }
}

#! Response type for verify archive operation
public class TarVerifyArchiveResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "entry_count": {
                "type": IntType,
                "display_name": "Entry Count",
                "short_desc": "Total entries in archive",
                "desc": "The number of entries in the archive",
            },
            "total_size": {
                "type": IntType,
                "display_name": "Total Size",
                "short_desc": "Total data size in bytes",
                "desc": "The total size of all file data read during verification",
            },
            "compression": {
                "type": StringType,
                "display_name": "Compression",
                "short_desc": "Compression method",
                "desc": "The compression method used by the archive",
            },
            "format": {
                "type": StringType,
                "display_name": "Format",
                "short_desc": "Archive format",
                "desc": "The archive format",
            },
            "valid": {
                "type": BoolType,
                "display_name": "Valid",
                "short_desc": "Whether archive is valid",
                "desc": "Returns `True` if the archive passed verification with no errors",
            },
            "errors": {
                "type": new ListDataType("VerifyErrorList", StringType, True),
                "display_name": "Errors",
                "short_desc": "List of errors found",
                "desc": "A list of error descriptions found during verification; empty if "
                    "the archive is valid",
            },
        };
    }

    constructor() : HashDataType("TarVerifyArchiveResponse") {
        addQoreFields(Fields);
    }
}
}
