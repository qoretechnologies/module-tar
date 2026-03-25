# -*- mode: qore; indent-tabs-mode: nil -*-
#! Qore TarDecryptArchiveDataProvider class definition

/** TarDecryptArchiveDataProvider.qc Copyright (C) 2026 Qore Technologies, s.r.o.

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
#! Decrypt archive data provider
public class TarDecryptArchiveDataProvider inherits AbstractDataProvider {
    public {
        const ProviderInfo = <DataProviderInfo>{
            "name": "decrypt",
            "desc": "Decrypt a TAR archive encrypted with AES-256-CBC.\n\n"
                "Auto-detects the encryption mode from the envelope:\n"
                "- **Password mode**: detected by `TENC` magic bytes at the start\n"
                "- **Key mode**: assumes `[IV] + [ciphertext]` format\n\n"
                "Provide the same `key` or `password` that was used for encryption",
            "type": "TarDecryptArchiveDataProvider",
            "supports_request": True,
        };

        #! Response type for action catalog output_type
        static TarDecryptArchiveResponseDataType ResponseType();
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
        return new TarDecryptArchiveRequestDataType();
    }

    private *AbstractDataProviderType getResponseTypeImpl() {
        return new TarDecryptArchiveResponseDataType();
    }

    private auto doRequestImpl(auto req, *hash<auto> request_options) {
        *binary encrypted_data = req.encrypted_data;
        if (!encrypted_data && req.encrypted_location) {
            encrypted_data = FileLocationHandler::getBinaryFileFromLocation(req.encrypted_location);
        }
        if (!encrypted_data && req.encrypted_path) {
            encrypted_data = ReadOnlyFile::readBinaryFile(req.encrypted_path);
        }
        if (!encrypted_data) {
            throw "TAR-ERROR", "one of 'encrypted_data', 'encrypted_path', or "
                "'encrypted_location' must be provided";
        }

        binary key;
        binary iv;
        binary ciphertext;

        # Auto-detect password vs key mode from magic bytes
        bool password_mode = encrypted_data.size() >= 4
            && encrypted_data.substr(0, 4) == TarEncryptArchiveDataProvider::PasswordMagic;

        if (password_mode) {
            if (!req.password) {
                throw "TAR-ERROR", "encrypted data uses password-based encryption; "
                    "provide 'password' to decrypt";
            }
            if (req.key) {
                throw "TAR-ERROR", "encrypted data uses password-based encryption; "
                    "provide 'password' not 'key'";
            }

            int min_size = 4 + TarEncryptArchiveDataProvider::SaltSize
                + TarEncryptArchiveDataProvider::IVSize + 16;
            if (encrypted_data.size() < min_size) {
                throw "TAR-ERROR", sprintf("encrypted data too small for password mode; "
                    "minimum %d bytes, got %d", min_size, encrypted_data.size());
            }

            binary salt = encrypted_data.substr(4, TarEncryptArchiveDataProvider::SaltSize);
            iv = encrypted_data.substr(4 + TarEncryptArchiveDataProvider::SaltSize,
                TarEncryptArchiveDataProvider::IVSize);
            ciphertext = encrypted_data.substr(4 + TarEncryptArchiveDataProvider::SaltSize
                + TarEncryptArchiveDataProvider::IVSize);

            key = TarEncryptArchiveDataProvider::deriveKey(req.password, salt);
        } else {
            # Key mode
            if (!req.key) {
                if (req.password) {
                    throw "TAR-ERROR", "encrypted data uses key-based encryption; "
                        "provide 'key' not 'password'";
                }
                throw "TAR-ERROR", "either 'key' or 'password' must be provided";
            }
            key = req.key;
            if (key.size() != TarEncryptArchiveDataProvider::KeySize) {
                throw "TAR-ERROR", sprintf("decryption key must be exactly %d bytes (AES-256); "
                    "got %d bytes", TarEncryptArchiveDataProvider::KeySize, key.size());
            }

            int min_size = TarEncryptArchiveDataProvider::IVSize + 16;
            if (encrypted_data.size() < min_size) {
                throw "TAR-ERROR", sprintf("encrypted data too small; minimum %d bytes, "
                    "got %d", min_size, encrypted_data.size());
            }

            iv = encrypted_data.substr(0, TarEncryptArchiveDataProvider::IVSize);
            ciphertext = encrypted_data.substr(TarEncryptArchiveDataProvider::IVSize);
        }

        binary archive_data = decrypt_to_binary(TarEncryptArchiveDataProvider::Cipher,
            ciphertext, key, iv);

        return {
            "archive_data": archive_data,
            "archive_size": archive_data.size(),
        };
    }
}

#! Request type for decrypt archive operation
public class TarDecryptArchiveRequestDataType inherits HashDataType {
    public {
        const Fields = {
            "encrypted_data": {
                "type": BinaryOrNothingType,
                "display_name": "Encrypted Data",
                "short_desc": "Encrypted archive binary data",
                "desc": "The encrypted tar archive as binary data",
            },
            "encrypted_path": {
                "type": StringOrNothingType,
                "display_name": "Encrypted File Path",
                "short_desc": "Path to encrypted archive file",
                "desc": "The filesystem path to the encrypted archive "
                    "(alternative to `encrypted_data`)",
                "example_value": "/path/to/archive.tar.gz.enc",
            },
            "encrypted_location": {
                "type": StringOrNothingType,
                "display_name": "Encrypted Location",
                "short_desc": "Encrypted archive location URL",
                "desc": "A FileLocationHandler location URL for the encrypted archive "
                    "(alternative to `encrypted_data` or `encrypted_path`)",
                "example_value": "file:///path/to/archive.tar.gz.enc",
            },
            "key": {
                "type": BinaryOrNothingType,
                "display_name": "Decryption Key",
                "short_desc": "AES-256 decryption key (32 bytes)",
                "desc": "A `32`-byte binary key for AES-256-CBC decryption. "
                    "Provide either `key` or `password`, matching the encryption mode",
            },
            "password": {
                "type": StringOrNothingType,
                "display_name": "Password",
                "short_desc": "Decryption password",
                "desc": "The password used during encryption. The encryption mode is "
                    "auto-detected from the envelope format",
            },
        };
    }

    constructor() : HashDataType("TarDecryptArchiveRequest") {
        addQoreFields(Fields);
        setRequiredGroups((("encrypted_data", "encrypted_path", "encrypted_location"),));
    }
}

#! Response type for decrypt archive operation
public class TarDecryptArchiveResponseDataType inherits HashDataType {
    public {
        const Fields = {
            "archive_data": {
                "type": BinaryType,
                "display_name": "Archive Data",
                "short_desc": "Decrypted archive binary",
                "desc": "The decrypted tar archive as binary data",
            },
            "archive_size": {
                "type": IntType,
                "display_name": "Archive Size",
                "short_desc": "Decrypted archive size in bytes",
                "desc": "The size of the decrypted archive in bytes",
            },
        };
    }

    constructor() : HashDataType("TarDecryptArchiveResponse") {
        addQoreFields(Fields);
    }
}
}
