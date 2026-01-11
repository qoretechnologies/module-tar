# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarExtractFileDataProvider class definition

/** TarExtractFileDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Extract single file data provider
public class TarExtractFileDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "extract",
            "desc": "Extract a single file from a TAR archive",
            "type": "TarExtractFileDataProvider",
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
        return new TarExtractFileRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarExtractFileResponseDataType();
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

        string entry_name = req.entry_name;
        string destination = req.destination ?? ".";

        tar.extractTo(entry_name, destination);
        tar.close();

        return {
            "extracted_to": destination,
            "entry_name": entry_name,
        };
    }
}

#! Request type for extract file operation
public class TarExtractFileRequestDataType inherits HashDataType {
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
                "desc": "The tar archive as binary data",
            },
            "entry_name": {
                "type": StringType,
                "display_name": "Entry Name",
                "short_desc": "File to extract",
                "desc": "The name/path of the entry to extract",
                "example_value": "data/config.json",
            },
            "destination": {
                "type": StringOrNothingType,
                "display_name": "Destination",
                "short_desc": "Destination path",
                "desc": "Where to extract the file (default: current directory)",
                "example_value": "/tmp/config.json",
            },
        };
    }

    constructor() : HashDataType("TarExtractFileRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for extract file operation
public class TarExtractFileResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "extracted_to": {
                "type": StringType,
                "display_name": "Extracted To",
                "short_desc": "Destination path",
                "desc": "Path where the file was extracted",
            },
            "entry_name": {
                "type": StringType,
                "display_name": "Entry Name",
                "short_desc": "Extracted entry name",
                "desc": "Name of the entry that was extracted",
            },
        };
    }

    constructor() : HashDataType("TarExtractFileResponse") {
        addQoreFields(Fields);
    }
}
}
