#include "../../Sources/Shared/PostScriptEncryption/PostScriptEncryptionCore.h"

#include <stdio.h>

int main(int argc, char **argv) {
    if (argc != 4) {
        fputs("usage: PostScriptEncryptionSmoke input output password\n", stderr);
        return 64;
    }
    return psencrypt_encrypt_postscript(
        argv[1],
        argv[2],
        argv[3]
    );
}
