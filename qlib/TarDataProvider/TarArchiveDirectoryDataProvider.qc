# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarArchiveDirectoryDataProvider class definition

/** TarArchiveDirectoryDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Archive directory data provider
public class TarArchiveDirectoryDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "archive",
            "desc": "Recursively archive a directory tree into a TAR archive, preserving file "
                "permissions and optionally following symlinks",
            "type": "TarArchiveDirectoryDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarArchiveDirectoryResponseDataType ResponseType();
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
        return new TarArchiveDirectoryRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarArchiveDirectoryResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        string directory_path = req.directory_path;
        if (!is_dir(directory_path)) {
            throw "TAR-ERROR", sprintf("directory does not exist: %y", directory_path);
        }

        bool follow_symlinks = req.follow_symlinks ?? False;

        # Set up create options
        *hash<TarCreateOptions> create_opts;
        if (req.compression) {
            create_opts = <TarCreateOptions>{
                "compression_method": getCompressionMethod(req.compression),
            };
        }
        if (req.format) {
            create_opts.format = getTarFormat(req.format);
        }

        TarFile tar;
        if (req.archive_path) {
            tar = new TarFile(req.archive_path, "w", create_opts);
        } else {
            tar = new TarFile(create_opts);
        }

        # Track counts and visited directories for symlink loop protection
        int file_count = 0;
        int dir_count = 0;
        hash<string, bool> visited;

        # Determine the archive prefix (base directory name or empty)
        string base_name = req.base_name ?? basename(directory_path);

        # Recursive walker
        code<nothing(string, string)> walk_dir = sub(string fs_path, string archive_prefix) {
            string canonical = realpath(fs_path);
            if (visited{canonical}) {
                return;
            }
            visited{canonical} = True;

            # Add directory entry
            string dir_entry = archive_prefix;
            if (!dir_entry.endsWith("/")) {
                dir_entry += "/";
            }
            tar.addDirectory(dir_entry);
            ++dir_count;

            Dir d();
            d.chdir(fs_path);

            # Process files
            foreach string name in (d.listFiles()) {
                string full_path = fs_path + "/" + name;
                string archive_name = archive_prefix + "/" + name;

                if (is_link(full_path) && !follow_symlinks) {
                    tar.addSymlink(archive_name, readlink(full_path));
                } else {
                    tar.addFile(archive_name, full_path);
                }
                ++file_count;
            }

            # Recurse into subdirectories
            foreach string name in (d.listDirs()) {
                string full_path = fs_path + "/" + name;
                string archive_name = archive_prefix + "/" + name;

                if (is_link(full_path) && !follow_symlinks) {
                    tar.addSymlink(archive_name, readlink(full_path));
                    ++file_count;
                } else {
                    walk_dir(full_path, archive_name);
                }
            }
        };

        walk_dir(directory_path, base_name);

        int entry_count = file_count + dir_count;

        if (req.archive_path) {
            tar.close();
            return {
                "archive_path": req.archive_path,
                "entry_count": entry_count,
                "file_count": file_count,
                "directory_count": dir_count,
                "compression": req.compression ?? "none",
            };
        }

        if (req.output_location) {
            binary archive_data = tar.toData();
            tar.close();
            FileLocationHandler::writeFileToLocation(req.output_location, archive_data);
            return {
                "output_location": req.output_location,
                "archive_data": archive_data,
                "entry_count": entry_count,
                "file_count": file_count,
                "directory_count": dir_count,
                "compression": req.compression ?? "none",
            };
        }

        binary archive_data = tar.toData();
        tar.close();
        return {
            "archive_data": archive_data,
            "entry_count": entry_count,
            "file_count": file_count,
            "directory_count": dir_count,
            "compression": req.compression ?? "none",
        };
    }
}

#! Request type for archive directory operation
public class TarArchiveDirectoryRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "directory_path": {
                "type": StringType,
                "display_name": "Directory Path",
                "short_desc": "Path to directory to archive",
                "desc": "The filesystem path to the directory to archive recursively",
                "example_value": "/path/to/directory",
            },
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Output archive file path",
                "desc": "The path where the tar archive will be created. If not specified, "
                    "returns binary data",
                "example_value": "/tmp/backup.tar.gz",
            },
            "output_location": {
                "type": StringOrNothingType,
                "display_name": "Output Location",
                "short_desc": "Output location URL",
                "desc": "A FileLocationHandler location URL where the archive will be written "
                    "(alternative to `archive_path`)",
                "example_value": "file:///tmp/backup.tar.gz",
            },
            "base_name": {
                "type": StringOrNothingType,
                "display_name": "Base Name",
                "short_desc": "Root directory name in archive",
                "desc": "The name used for the root directory entry in the archive. If not "
                    "specified, uses the basename of `directory_path`",
                "example_value": "project",
            },
            "compression": {
                "type": StringOrNothingType,
                "display_name": "Compression",
                "short_desc": "Compression method",
                "desc": "The compression method to use for the output archive",
                "allowed_values": AllowedCompressionValues,
            },
            "format": {
                "type": StringOrNothingType,
                "display_name": "Format",
                "short_desc": "TAR format",
                "desc": "The tar format to use for the output archive",
                "allowed_values": AllowedFormatValues,
            },
            "follow_symlinks": {
                "type": SoftBoolOrNothingType,
                "display_name": "Follow Symlinks",
                "short_desc": "Follow symbolic links",
                "desc": "If `True`, follows symbolic links and archives the target file contents. "
                    "If `False` (default), archives symlinks as symlink entries",
                "default_value": False,
            },
        };
    }

    constructor() : HashDataType("TarArchiveDirectoryRequest") {
        addQoreFields(Fields);
    }
}

#! Response type for archive directory operation
public class TarArchiveDirectoryResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to created archive",
                "desc": "The filesystem path where the archive was created",
            },
            "output_location": {
                "type": StringOrNothingType,
                "display_name": "Output Location",
                "short_desc": "Output location URL",
                "desc": "The location URL where the archive was written",
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
                "short_desc": "Total entries added",
                "desc": "Total number of entries added to the archive (files + directories)",
            },
            "file_count": {
                "type": IntType,
                "display_name": "File Count",
                "short_desc": "Files added",
                "desc": "Number of files (including symlinks) added to the archive",
            },
            "directory_count": {
                "type": IntType,
                "display_name": "Directory Count",
                "short_desc": "Directories added",
                "desc": "Number of directory entries added to the archive",
            },
            "compression": {
                "type": StringType,
                "display_name": "Compression",
                "short_desc": "Compression method used",
                "desc": "The compression method that was applied",
            },
        };
    }

    constructor() : HashDataType("TarArchiveDirectoryResponse") {
        addQoreFields(Fields);
    }
}
}
