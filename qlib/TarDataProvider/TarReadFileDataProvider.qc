# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarReadFileDataProvider class definition

/** TarReadFileDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Read file from archive data provider
public class TarReadFileDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "read",
            "desc": "Read file contents from a TAR archive without extracting",
            "type": "TarReadFileDataProvider",
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
        return new TarReadFileRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarReadFileResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        @assert(req.archive_data || req.archive_path, "Either archive_path or archive_data must be provided");
        @assert(req.entry_name.val(), "entry_name is required and cannot be empty");

        @debug {
            printf("TarReadFile: entry_name=%y as_text=%y encoding=%y\n",
                req.entry_name, req.as_text ?? False, req.encoding ?? "UTF-8");
        }

        TarFile tar;
        if (req.archive_data) {
            tar = new TarFile(req.archive_data);
        } else {
            tar = new TarFile(req.archive_path, "r");
        }

        binary content = tar.read(req.entry_name);
        *hash<TarEntryInfo> info = tar.getEntry(req.entry_name);
        tar.close();

        if (req.as_text) {
            return {
                "content": content.toString(req.encoding ?? "UTF-8"),
                "size": content.size(),
                "entry_info": info,
            };
        }

        return {
            "content": content,
            "size": content.size(),
            "entry_info": info,
        };
    }
}

#! Request type for read file operation
public class TarReadFileRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive file",
                "desc": "The filesystem path to the tar archive",
                "example_value": "/path/to/archive.tar.gz",
            },
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "Binary archive data",
                "desc": "The tar archive as binary data (alternative to archive_path)",
            },
            "entry_name": {
                "type": StringType,
                "display_name": "Entry Name",
                "short_desc": "Name of file to read",
                "desc": "The path/name of the entry to read from the archive",
                "example_value": "data/config.json",
            },
            "as_text": {
                "type": SoftBoolOrNothingType,
                "display_name": "Read as Text",
                "short_desc": "Return content as text string",
                "desc": "If true, returns content as text string instead of binary (default: false)",
                "example_value": False,
            },
            "encoding": {
                "type": StringOrNothingType,
                "display_name": "Encoding",
                "short_desc": "Text encoding for as_text mode",
                "desc": "Character encoding to use when as_text is true. "
                    "Common encodings: UTF-8, ISO-8859-1, ASCII, UTF-16, Windows-1252 (default: UTF-8)",
                "example_value": "UTF-8",
                "allowed_values": AllowedEncodingValues,
            },
        };
    }

    constructor() : HashDataType("TarReadFileRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for read file operation
public class TarReadFileResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "content": {
                "type": AutoType,
                "display_name": "Content",
                "short_desc": "File content",
                "desc": "The content of the file (binary or string depending on as_text)",
            },
            "size": {
                "type": IntType,
                "display_name": "Size",
                "short_desc": "Content size in bytes",
                "desc": "Size of the content in bytes",
            },
            "entry_info": {
                "type": AutoHashOrNothingType,
                "display_name": "Entry Info",
                "short_desc": "Entry metadata",
                "desc": "Metadata about the entry (name, permissions, timestamps, etc.)",
            },
        };
    }

    constructor() : HashDataType("TarReadFileResponse") {
        addQoreFields(Fields);
    }
}
}
