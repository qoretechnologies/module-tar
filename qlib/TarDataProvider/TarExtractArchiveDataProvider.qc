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
            "desc": "Extract contents from a TAR archive with optional `include`/`exclude` glob-style "
                "filename filters for whitelisting and/or blacklisting entries",
            "type": "TarExtractArchiveDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarExtractArchiveResponseDataType ResponseType();
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
            throw "TAR-ERROR", "one of 'archive_path', 'archive_data', or 'archive_location' must be provided";
        }

        string destination = req.destination ?? ".";

        hash<TarExtractOptions> extract_opts = <TarExtractOptions>{
            "destination": destination,
            "preserve_permissions": req.preserve_permissions ?? True,
            "preserve_times": req.preserve_times ?? True,
            "overwrite": req.overwrite ?? False,
            "create_directories": True,
        };
        if (req.include) {
            extract_opts.include = req.include;
        }
        if (req.exclude) {
            extract_opts.exclude = req.exclude;
        }
        if (req.strip_count) {
            extract_opts.strip_count = req.strip_count;
        }

        list<hash<TarEntryInfo>> all_entries = tar.entries();
        list<string> extracted_names = tar.extractAll(extract_opts);
        tar.close();

        # Build response entries list
        list<hash<TarEntryInfo>> entries;
        if (req.include || req.exclude || req.strip_count) {
            # When filtering or stripping is active, use extracted_names from C++ as
            # source of truth; with strip_count the names are transformed so we can't
            # match against all_entries by name
            hash<string, bool> name_set = map {$1: True}, extracted_names;
            entries = (map $1, all_entries, name_set{$1.name});
            # If stripping changed names such that no all_entries match, fall back to
            # reporting extracted_names count directly
            if (!entries && extracted_names) {
                entries = (map <TarEntryInfo>{"name": $1}, extracted_names);
            }
        } else {
            entries = all_entries;
        }

        @debug {
            printf("TarExtractArchive: extracted %d entries to %y\n",
                extracted_names.size(), destination);
        }

        return {
            "destination": destination,
            "extracted_count": extracted_names.size(),
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
            "archive_location": {
                "type": StringOrNothingType,
                "display_name": "Archive Location",
                "short_desc": "Archive location URL",
                "desc": "A FileLocationHandler location URL for the tar archive (alternative to archive_path or archive_data)",
                "example_value": "file:///path/to/archive.tar.gz",
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
                "desc": "If `true`, restores original file permissions",
                "default_value": True,
            },
            "preserve_times": {
                "type": SoftBoolType,
                "display_name": "Preserve Times",
                "short_desc": "Restore modification times",
                "desc": "If `true`, restores original modification times",
                "default_value": True,
            },
            "overwrite": {
                "type": SoftBoolType,
                "display_name": "Overwrite",
                "short_desc": "Overwrite existing files",
                "desc": "If `true`, overwrites existing files",
                "default_value": False,
            },
            "include": {
                "type": new ListDataType("IncludePatternList", StringType, True),
                "display_name": "Include Patterns",
                "short_desc": "Glob patterns for files to include",
                "desc": "A list of glob-style patterns; only entries matching at least one pattern will be "
                    "extracted. If not provided, all entries are included by default.\n\n"
                    "**Supported wildcards**: `*` matches any characters (including `/`), "
                    "`?` matches any single character, `[abc]` matches one character from the set",
                "example_value": ("*.txt", "docs/*"),
            },
            "exclude": {
                "type": new ListDataType("ExcludePatternList", StringType, True),
                "display_name": "Exclude Patterns",
                "short_desc": "Glob patterns for files to exclude",
                "desc": "A list of glob-style patterns; entries matching any pattern will be skipped. "
                    "Exclude patterns are applied after `include` patterns.\n\n"
                    "**Supported wildcards**: `*` matches any characters (including `/`), "
                    "`?` matches any single character, `[abc]` matches one character from the set",
                "example_value": ("*.log", "tmp/*"),
            },
            "strip_count": {
                "type": IntOrNothingType,
                "display_name": "Strip Components",
                "short_desc": "Strip N leading path components",
                "desc": "Number of leading path components to strip from entry names during "
                    "extraction. For example, with `strip_count` = `1`, the entry "
                    "`project/src/main.c` becomes `src/main.c`. Entries with fewer components "
                    "than `strip_count` are skipped",
                "example_value": 1,
            },
        };
    }

    constructor() : HashDataType("TarExtractArchiveRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("archive_path", "archive_data", "archive_location"),));
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
