# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarCreateArchiveDataProvider class definition

/** TarCreateArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Create archive data provider
public class TarCreateArchiveDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "create",
            "desc": "Create a new TAR archive",
            "type": "TarCreateArchiveDataProvider",
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
        return new TarCreateArchiveRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarCreateArchiveResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        int compression = getCompressionMethod(req.compression);
        int format = getTarFormat(req.format);
        int level = req.compression_level ?? -1;

        hash<TarCreateOptions> create_opts = <TarCreateOptions>{
            "compression_method": compression,
            "compression_level": level,
            "format": format,
        };

        TarFile tar;
        bool in_memory = !req.archive_path;

        if (in_memory) {
            tar = new TarFile(create_opts);
        } else {
            tar = new TarFile(req.archive_path, "w", create_opts);
        }

        int entry_count = 0;

        # Add entries from files hash
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
                entry_count++;
            }
        }

        # Add directories
        if (req.directories) {
            foreach string dir in (req.directories) {
                string dir_name = dir;
                if (!dir_name.endsWith("/")) {
                    dir_name += "/";
                }
                tar.addDirectory(dir_name);
                entry_count++;
            }
        }

        *binary archive_data;
        if (in_memory) {
            archive_data = tar.toData();
        }

        tar.close();

        if (in_memory) {
            return {
                "archive_data": archive_data,
                "entry_count": entry_count,
                "compression": req.compression ?? "none",
            };
        }

        return {
            "archive_path": req.archive_path,
            "entry_count": entry_count,
            "compression": req.compression ?? "none",
        };
    }
}

#! Request type for create archive operation
public class TarCreateArchiveRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Output archive file path",
                "desc": "The path where the tar archive will be created. If not specified, returns binary data.",
                "example_value": "/tmp/backup.tar.gz",
            },
            "compression": {
                "type": StringOrNothingType,
                "display_name": "Compression Method",
                "short_desc": "Archive compression type",
                "desc": "The compression method to use: none, gzip, bzip2, xz, zstd, or lz4",
                "example_value": "gzip",
                "allowed_values": ("none", "gzip", "bzip2", "xz", "zstd", "lz4"),
            },
            "compression_level": {
                "type": IntOrNothingType,
                "display_name": "Compression Level",
                "short_desc": "Compression strength (1-9)",
                "desc": "Compression level from 1 (fastest) to 9 (best). Default depends on method.",
                "example_value": 6,
            },
            "format": {
                "type": StringOrNothingType,
                "display_name": "Archive Format",
                "short_desc": "TAR format variant",
                "desc": "The tar format to use: ustar, pax, gnu, or v7",
                "example_value": "pax",
                "allowed_values": ("ustar", "pax", "gnu", "v7"),
            },
            "files": {
                "type": new ListDataType("FileEntryList", AutoHashType, True),
                "display_name": "Files",
                "short_desc": "Files to add to archive",
                "desc": "List of file entries. Each entry should have 'name' and one of: 'data' (binary), 'text' (string), or 'source_path' (file path)",
                "example_value": ({"name": "hello.txt", "text": "Hello World"},),
            },
            "directories": {
                "type": new ListDataType("DirList", StringType, True),
                "display_name": "Directories",
                "short_desc": "Empty directories to create",
                "desc": "List of directory entries to add (without content)",
                "example_value": ("subdir/", "another/path/"),
            },
        };
    }

    constructor() : HashDataType("TarCreateArchiveRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for create archive operation
public class TarCreateArchiveResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to created archive",
                "desc": "The filesystem path where the archive was created",
            },
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "Archive binary data",
                "desc": "The archive as binary data (when no path was specified)",
            },
            "entry_count": {
                "type": IntType,
                "display_name": "Entry Count",
                "short_desc": "Number of entries added",
                "desc": "Total number of entries added to the archive",
            },
            "compression": {
                "type": StringType,
                "display_name": "Compression",
                "short_desc": "Compression method used",
                "desc": "The compression method that was applied",
            },
        };
    }

    constructor() : HashDataType("TarCreateArchiveResponse") {
        addQoreFields(Fields);
    }
}
}
