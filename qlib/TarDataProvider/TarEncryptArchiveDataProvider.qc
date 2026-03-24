# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarEncryptArchiveDataProvider class definition

/** TarEncryptArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Encrypt archive data provider
public class TarEncryptArchiveDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "encrypt",
            "desc": "Encrypt a TAR archive with AES-256-CBC.\n\n"
                "The output format is a `16`-byte random IV followed by the AES-256-CBC ciphertext. "
                "Use the **decrypt** action with the same key to recover the original archive",
            "type": "TarEncryptArchiveDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarEncryptArchiveResponseDataType ResponseType();

        #! AES-256 key size in bytes
        const KeySize = 32;
        #! AES-256-CBC IV size in bytes
        const IVSize = 16;
        #! Cipher algorithm identifier
        const Cipher = "aes-256-cbc";
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
        return new TarEncryptArchiveRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarEncryptArchiveResponseDataType();
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

        binary key = req.key;
        if (key.size() != KeySize) {
            throw "TAR-ERROR", sprintf("encryption key must be exactly %d bytes (AES-256); "
                "got %d bytes", KeySize, key.size());
        }

        binary iv = get_random_bytes(IVSize);
        binary ciphertext = encrypt(Cipher, archive_data, key, iv);

        # Envelope: [IV][ciphertext]
        binary encrypted_data = iv + ciphertext;

        return {
            "encrypted_data": encrypted_data,
            "encrypted_size": encrypted_data.size(),
            "original_size": archive_data.size(),
        };
    }
}

#! Request type for encrypt archive operation
public class TarEncryptArchiveRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryOrNothingType,
                "display_name": "Archive Data",
                "short_desc": "TAR archive binary data",
                "desc": "The tar archive as binary data to encrypt",
            },
            "archive_path": {
                "type": StringOrNothingType,
                "display_name": "Archive Path",
                "short_desc": "Path to the tar archive",
                "desc": "The filesystem path to the tar archive (alternative to `archive_data`)",
                "example_value": "/path/to/archive.tar.gz",
            },
            "archive_location": {
                "type": StringOrNothingType,
                "display_name": "Archive Location",
                "short_desc": "Archive location URL",
                "desc": "A FileLocationHandler location URL for the tar archive "
                    "(alternative to `archive_data` or `archive_path`)",
                "example_value": "file:///path/to/archive.tar.gz",
            },
            "key": {
                "type": BinaryType,
                "display_name": "Encryption Key",
                "short_desc": "AES-256 encryption key (32 bytes)",
                "desc": "A `32`-byte binary key for AES-256-CBC encryption",
            },
        };
    }

    constructor() : HashDataType("TarEncryptArchiveRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("archive_data", "archive_path", "archive_location"),));
    }
}

#! Response type for encrypt archive operation
public class TarEncryptArchiveResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "encrypted_data": {
                "type": BinaryType,
                "display_name": "Encrypted Data",
                "short_desc": "Encrypted archive binary",
                "desc": "The encrypted archive as binary data (IV + ciphertext)",
            },
            "encrypted_size": {
                "type": IntType,
                "display_name": "Encrypted Size",
                "short_desc": "Encrypted data size in bytes",
                "desc": "The total size of the encrypted output including the IV",
            },
            "original_size": {
                "type": IntType,
                "display_name": "Original Size",
                "short_desc": "Original archive size in bytes",
                "desc": "The size of the original unencrypted archive",
            },
        };
    }

    constructor() : HashDataType("TarEncryptArchiveResponse") {
        addQoreFields(Fields);
    }
}
}
