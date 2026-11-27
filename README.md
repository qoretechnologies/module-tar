# Qore TAR Module

This module provides TAR archive functionality for the Qore programming language.

## Features

- Create and extract TAR archives
- Support for multiple compression methods: gzip, bzip2, xz, zstd, lz4
- Support for multiple TAR formats: ustar, pax, GNU, V7
- In-memory archive operations
- Streaming API for large files
- Stream-based I/O (read/write from Qore streams)
- File metadata preservation (permissions, ownership, timestamps)
- Support for special file types (symlinks, hardlinks, sparse files)
- Archive encryption and multi-volume support

## Requirements

- Qore 2.0 or later
- libarchive 3.0 or later
- OpenSSL (optional, for encryption support)

## Building

```bash
mkdir build && cd build
cmake ..
make
sudo make install
```

## Quick Start

### Creating an Archive

```qore
#!/usr/bin/env qore

%requires tar

# Create a gzip-compressed archive
TarFile tar("backup.tar.gz", "w");
tar.add("file.txt", "Hello, World!");
tar.addFile("docs/readme.txt", "/path/to/readme.txt");
tar.addDirectory("empty_dir/");
tar.close();
```

### Reading an Archive

```qore
#!/usr/bin/env qore

%requires tar

# Open and read archive
TarFile tar("backup.tar.gz", "r");

# List entries
for (hash<TarEntryInfo> entry : tar.entries()) {
    printf("%s: %d bytes\n", entry.name, entry.size);
}

# Extract a specific file
binary data = tar.read("file.txt");
tar.close();
```

### Extracting an Archive

```qore
#!/usr/bin/env qore

%requires tar

TarFile tar("backup.tar.gz", "r");
tar.extractAll({"destination": "/tmp/extracted"});
tar.close();
```

### In-Memory Archives

```qore
#!/usr/bin/env qore

%requires tar

# Create archive in memory
TarFile tar();
tar.add("data.txt", "Some data");
binary archive_data = tar.toData();

# Read from memory
TarFile tar2(archive_data);
string content = tar2.readText("data.txt");
```

## Data Provider

The module includes `TarDataProvider` for use with Qore's data provider framework:

```qore
%requires TarDataProvider

# Get the data provider factory and navigate to the action
AbstractDataProvider dp = DataProvider::getFactoryObjectFromStringEx("tar{}/archive/create");

# Execute the action
hash<auto> result = dp.doRequest({
    "archive_path": "/tmp/backup.tar.gz",
    "compression": "gzip",
    "files": (
        {"name": "file.txt", "text": "Hello, World!"},
    ),
});
```

The `archive/extract` and `file/extract` actions create missing directories unless their `create_directories`
option is `false`.

## qtar

The module installs `qtar`, a command-line tool for archive operations (`qtar --help` lists the commands, and
`qtar <command> --help` the options of a command):

```bash
qtar create backup.tar.gz project/
qtar extract backup.tar.gz -C restore/
# extract only into existing directories: neither restore/ nor missing parent directories are created
qtar extract backup.tar.gz -C restore/ --no-create-dirs
```

## License

MIT License - see COPYING.MIT for details.

## Copyright

Copyright 2026 Qore Technologies, s.r.o.

Develop CI
----------

On develop, each platform can reuse its successful full job for the same Git
tree and Qore environment, including after a squash merge. Both platforms
must have passed in the same prior pipeline. Reused statuses link to the
original jobs. A changed fingerprint or missing evidence runs the full suite.
Set QORE_CI_FORCE_FULL=1 to force both suites.
