#ifndef PostScriptEncryptionCore_h
#define PostScriptEncryptionCore_h

enum {
    PSENCRYPT_SUCCESS = 0,
    PSENCRYPT_INVALID_ARGUMENT = 1,
    PSENCRYPT_PASSWORD_EMPTY = 2,
    PSENCRYPT_PASSWORD_TOO_LONG = 3,
    PSENCRYPT_PASSWORD_UNSUPPORTED_CHARACTER = 4,
    PSENCRYPT_PASSWORD_RESERVED = 5,
    PSENCRYPT_INPUT_OPEN_FAILED = 6,
    PSENCRYPT_INPUT_NOT_POSTSCRIPT = 7,
    PSENCRYPT_OUTPUT_EXISTS = 8,
    PSENCRYPT_OUTPUT_OPEN_FAILED = 9,
    PSENCRYPT_RANDOM_FAILED = 10,
    PSENCRYPT_KEY_DERIVATION_FAILED = 11,
    PSENCRYPT_CRYPTO_FAILED = 12,
    PSENCRYPT_READ_FAILED = 13,
    PSENCRYPT_WRITE_FAILED = 14
};

int psencrypt_validate_password(const char *password);

int psencrypt_encrypt_postscript(const char *input_path,
                                 const char *output_path,
                                 const char *password);

#endif /* PostScriptEncryptionCore_h */
