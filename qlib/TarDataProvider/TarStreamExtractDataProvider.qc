# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarStreamExtractDataProvider class definition

/** TarStreamExtractDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Stream extract data provider
public class TarStreamExtractDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "extract",
            "desc": "Open a streaming input for reading a file from a TAR archive without "
                "loading the entire file into memory.\n\n"
                "**Important**: the `tar_file` object in the response must be kept alive "
                "while reading from the stream",
            "type": "TarStreamExtractDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarStreamExtractResponseDataType ResponseType();
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
        return new TarStreamExtractRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarStreamExtractResponseDataType();
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

        string entry_name = req.entry_name;
        @assert(entry_name.val());

        *hash<TarEntryInfo> info = tar.getEntry(entry_name);
        if (!info) {
            tar.close();
            throw "TAR-ERROR", sprintf("entry %y not found in archive", entry_name);
        }

        TarInputStream stream = tar.getInputStream(entry_name);

        return {
            "stream": stream,
            "entry_name": info.name,
            "size": info.size,
            "tar_file": tar,
        };
    }
}

#! Request type for stream extract operation
public class TarStreamExtractRequestDataType inherits HashDataType {
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
            "entry_name": {
                "type": StringType,
                "display_name": "Entry Name",
                "short_desc": "Name of entry to stream",
                "desc": "The full path name of the entry to read from the archive",
                "example_value": "data/large-file.bin",
            },
        };
    }

    constructor() : HashDataType("TarStreamExtractRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("archive_path", "archive_data", "archive_location"),));
    }
}

#! Response type for stream extract operation
public class TarStreamExtractResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "stream": {
                "type": AutoType,
                "display_name": "Input Stream",
                "short_desc": "TarInputStream for reading entry data",
                "desc": "A `TarInputStream` object implementing the `InputStream` interface "
                    "for reading entry data in chunks",
            },
            "entry_name": {
                "type": StringType,
                "display_name": "Entry Name",
                "short_desc": "Name of the entry",
                "desc": "The name of the entry being streamed",
            },
            "size": {
                "type": IntType,
                "display_name": "Size",
                "short_desc": "Entry size in bytes",
                "desc": "The uncompressed size of the entry in bytes",
            },
            "tar_file": {
                "type": AutoType,
                "display_name": "TAR File Handle",
                "short_desc": "Archive handle (keep alive while streaming)",
                "desc": "The `TarFile` object that owns the stream. **Must be kept alive** "
                    "while reading from the stream; releasing this reference invalidates "
                    "the stream",
            },
        };
    }

    constructor() : HashDataType("TarStreamExtractResponse") {
        addQoreFields(Fields);
    }
}
}
