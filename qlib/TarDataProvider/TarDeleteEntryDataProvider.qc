# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarDeleteEntryDataProvider class definition

/** TarDeleteEntryDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Delete entry data provider
public class TarDeleteEntryDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "delete",
            "desc": "Delete an entry from a TAR archive by recreating the archive without the "
                "specified entry, preserving all metadata on remaining entries",
            "type": "TarDeleteEntryDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarDeleteEntryResponseDataType ResponseType();
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
        return new TarDeleteEntryRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarDeleteEntryResponseDataType();
    }

    #! Converts TarEntryInfo metadata to TarAddOptions for preserving metadata during copy
    private static hash<TarAddOptions> entryInfoToAddOptions(hash<TarEntryInfo> info) {
        return <TarAddOptions>{
            "mode": info.mode,
            "uid": info.uid,
            "gid": info.gid,
            "uname": info.uname,
            "gname": info.gname,
            "modified": info.modified,
        };
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
            throw "TAR-ERROR", "one of 'archive_data', 'archive_path', or 'archive_location' "
                "must be provided";
        }

        string entry_name = req.entry_name;
        if (!entry_name.val()) {
            throw "ASSERTION-ERROR", "entry_name is required and cannot be empty";
        }

        TarFile src(archive_data);
        list<hash<TarEntryInfo>> entries = src.entries();

        # Check if entry exists
        if (!src.hasEntry(entry_name)) {
            src.close();
            return {
                "archive_data": archive_data,
                "archive_size": archive_data.size(),
                "deleted": False,
                "remaining_count": entries.size(),
            };
        }

        # Create new archive, copying all entries except the target
        *hash<TarCreateOptions> create_opts;
        if (req.compression) {
            create_opts = <TarCreateOptions>{
                "compression_method": getCompressionMethod(req.compression),
            };
        }
        if (req.format) {
            create_opts.format = getTarFormat(req.format);
        }

        TarFile dest(create_opts);
        int remaining = 0;

        foreach hash<TarEntryInfo> entry in (entries) {
            if (entry.name == entry_name) {
                continue;
            }

            hash<TarAddOptions> add_opts = entryInfoToAddOptions(entry);

            if (entry.is_directory) {
                dest.addDirectory(entry.name, add_opts);
            } else if (entry.is_symlink) {
                dest.addSymlink(entry.name, entry.link_target, add_opts);
            } else if (entry.is_hardlink) {
                dest.addHardlink(entry.name, entry.link_target, add_opts);
            } else {
                binary content = src.read(entry.name);
                dest.add(entry.name, content, add_opts);
            }
            ++remaining;
        }

        src.close();
        binary result_data = dest.toData();
        dest.close();

        return {
            "archive_data": result_data,
            "archive_size": result_data.size(),
            "deleted": True,
            "remaining_count": remaining,
        };
    }
}

#! Request type for delete entry operation
public class TarDeleteEntryRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "TAR archive binary data",
                "desc": "The tar archive as binary data",
            },
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive (alternative to `archive_data`)",
                "example_value": "/path/to/archive.tar",
            },
            "archive_location": {
                "type": StringOrNothingType,
                "display_name": "Archive Location",
                "short_desc": "Archive location URL",
                "desc": "A FileLocationHandler location URL for the tar archive "
                    "(alternative to `archive_data` or `archive_path`)",
                "example_value": "file:///path/to/archive.tar",
            },
            "entry_name": {
                "type": StringType,
                "display_name": "Entry Name",
                "short_desc": "Name of entry to delete",
                "desc": "The full path name of the entry to delete from the archive",
                "example_value": "old-file.txt",
            },
            "compression": {
                "type": StringOrNothingType,
                "display_name": "Output Compression",
                "short_desc": "Compression for output archive",
                "desc": "Compression method for the output archive. If not specified, the output "
                    "is uncompressed",
                "allowed_values": AllowedCompressionValues,
            },
            "format": {
                "type": StringOrNothingType,
                "display_name": "Output Format",
                "short_desc": "TAR format for output archive",
                "desc": "The tar format for the output archive",
                "allowed_values": AllowedFormatValues,
            },
        };
    }

    constructor() : HashDataType("TarDeleteEntryRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("archive_data", "archive_path", "archive_location"),));
    }
}

#! Response type for delete entry operation
public class TarDeleteEntryResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryType,
                "display_name": "Archive Data",
                "short_desc": "Modified archive binary",
                "desc": "The archive binary data with the entry removed (or unchanged if entry "
                    "was not found)",
            },
            "archive_size": {
                "type": IntType,
                "display_name": "Archive Size",
                "short_desc": "Archive size in bytes",
                "desc": "The size of the output archive in bytes",
            },
            "deleted": {
                "type": BoolType,
                "display_name": "Deleted",
                "short_desc": "Whether the entry was found and deleted",
                "desc": "Returns `True` if the entry was found and removed, `False` if the "
                    "entry was not found in the archive",
            },
            "remaining_count": {
                "type": IntType,
                "display_name": "Remaining Count",
                "short_desc": "Number of entries remaining",
                "desc": "The number of entries remaining in the archive after deletion",
            },
        };
    }

    constructor() : HashDataType("TarDeleteEntryResponse") {
        addQoreFields(Fields);
    }
}
}
