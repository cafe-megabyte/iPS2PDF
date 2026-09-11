/*
 * PostScriptEncryptionCore.c
 *
 * Adapted from the Apache-2.0-licensed psencrypt project. This modified
 * version exposes a library API for Apple platforms and supports only
 * encryption of existing PostScript programs; the text typesetter and
 * command-line interface were intentionally removed.
 */

#include "PostScriptEncryptionCore.h"

#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonHMAC.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <CommonCrypto/CommonRandom.h>

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SALT_LEN 16
#define IV_LEN 16
#define KEY_LEN 32
#define TAG_LEN 32
#define IO_CHUNK 4096
#define HEX_CHUNK 2048
#define DEFAULT_ITERATIONS 20000
#define MAX_PASSWORD_LEN 1023
#define PASSWORD_PLACEHOLDER "secret_password"
#define WRONG_PASSWORD_MESSAGE "Wrong Password"

static const unsigned char AES_KEY_LABEL[] = "psencrypt-v2/aes-256-ctr";
static const unsigned char MAC_KEY_LABEL[] = "psencrypt-v2/hmac-sha-256";

typedef CCHmacContext *PS_HMAC_CTX;
typedef CCCryptorRef PS_CIPHER_CTX;

static void ps_cleanse(void *ptr, size_t len) {
    volatile unsigned char *p = ptr;
    while (len--) *p++ = 0;
}

static int ps_random(unsigned char *out, size_t len) {
    return CCRandomGenerateBytes(out, len) == kCCSuccess;
}

static int ps_pbkdf2(const char *password, const unsigned char *salt,
                     size_t salt_len, int iterations,
                     unsigned char out[KEY_LEN]) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, password, strlen(password),
                               salt, salt_len, kCCPRFHmacAlgSHA256,
                               (unsigned)iterations, out, KEY_LEN) == kCCSuccess;
}

static PS_HMAC_CTX ps_hmac_new(const unsigned char *key, size_t keylen) {
    CCHmacContext *ctx = malloc(sizeof *ctx);
    if (ctx) CCHmacInit(ctx, kCCHmacAlgSHA256, key, keylen);
    return ctx;
}

static int ps_hmac_update(PS_HMAC_CTX ctx, const unsigned char *p, size_t n) {
    CCHmacUpdate(ctx, p, n);
    return 1;
}

static int ps_hmac_final(PS_HMAC_CTX ctx, unsigned char out[TAG_LEN]) {
    CCHmacFinal(ctx, out);
    return 1;
}

static void ps_hmac_free(PS_HMAC_CTX ctx) {
    if (ctx) {
        ps_cleanse(ctx, sizeof *ctx);
        free(ctx);
    }
}

static PS_CIPHER_CTX ps_cipher_new(const unsigned char key[KEY_LEN],
                                    const unsigned char iv[IV_LEN]) {
    CCCryptorRef ctx = NULL;
    if (CCCryptorCreateWithMode(kCCEncrypt, kCCModeCTR, kCCAlgorithmAES,
                               ccNoPadding, iv, key, KEY_LEN, NULL, 0, 0,
                               kCCModeOptionCTR_BE, &ctx) != kCCSuccess) {
        return NULL;
    }
    return ctx;
}

static int ps_cipher_update(PS_CIPHER_CTX ctx,
                            const unsigned char *in, size_t inlen,
                            unsigned char *out, size_t outcap, size_t *outlen) {
    return CCCryptorUpdate(ctx, in, inlen, out, outcap, outlen) == kCCSuccess;
}

static int ps_cipher_final(PS_CIPHER_CTX ctx, unsigned char *out,
                           size_t outcap, size_t *outlen) {
    (void)ctx;
    (void)out;
    (void)outcap;
    *outlen = 0;
    return 1;
}

static void ps_cipher_free(PS_CIPHER_CTX ctx) {
    if (ctx) CCCryptorRelease(ctx);
}

static int ps_derive_key(const unsigned char master[KEY_LEN],
                         const unsigned char *label, size_t label_len,
                         unsigned char out[KEY_LEN]) {
    PS_HMAC_CTX ctx = ps_hmac_new(master, KEY_LEN);
    if (!ctx) return 0;
    int ok = ps_hmac_update(ctx, label, label_len) && ps_hmac_final(ctx, out);
    ps_hmac_free(ctx);
    if (!ok) ps_cleanse(out, KEY_LEN);
    return ok;
}

static const char PS_RUNTIME_PREFIX[] =
    "% ---- Self-contained runtime (no private crypto filters) ----\n"
    "% Selects native wide-integer or portable 16-bit-halves SHA arithmetic.\n"
    "% PBKDF2 derives one master key; labeled HMACs derive separate AES and MAC keys.\n"
    "% The arithmetic capability probe is silent and independent of product names.\n"
    "% Scratch names are protected while procedures are bound so private interpreter\n"
    "% operators (for example, Distiller's /v) cannot be captured accidentally.\n"
    "\n"
    "/psenScratchNames [\n"
    "  /rrn /rrx /sb /i /j /v /x /s0 /s1 /a /b /c /d /e /f /g /h\n"
    "  /S1 /ch /t1 /S0 /maj /t2 /origHi /origLo /bitHi /bitLo /dg\n"
    "  /hk /kb /hin /pbIter /pbIndex /pbSalt /ib /U /T /q /key /bytes\n"
    "  /rci /tmp /t /xb /inp /st /rnd /tt /a0 /a1 /a2 /a3 /mx /u\n"
    "  /off /ctr /gc /cp /rb /cb /encChunk /plainChunk /byteIndex\n"
    "  /cipherByte /psenWideMath /psenProbeValue\n"
    "] def\n"
    "psenScratchNames { 0 def } forall\n"
    "\n"
    "/M32 16#ffffffff def\n"
    "/u32 { M32 and } bind def\n"
    "/psenWideMath false def\n"
    "mark {\n"
    "  /psenProbeValue 16#7fffffff 10 mul 5 add def\n"
    "  /psenWideMath psenProbeValue type /integertype eq M32 0 gt and def\n"
    "} stopped {\n"
    "  /psenWideMath false def\n"
    "  $error /newerror false put\n"
    "} if\n"
    "cleartomark\n"
    "psenWideMath {\n"
    "  /add32 systemdict /add get def\n"
    "} {\n"
    "  /add32 {\n"
    "    2 copy 16#ffff and exch 16#ffff and add\n"
    "    3 1 roll\n"
    "    -16 bitshift 16#ffff and\n"
    "    exch -16 bitshift 16#ffff and add\n"
    "    1 index -16 bitshift add 16#ffff and 16 bitshift\n"
    "    exch 16#ffff and or\n"
    "  } bind def\n"
    "} ifelse\n"
    "/rotr {\n"
    "  /rrn exch def /rrx exch M32 and def\n"
    "  rrx rrn neg bitshift\n"
    "  rrx 32 rrn sub bitshift\n"
    "  or M32 and\n"
    "} bind def\n"
    "\n"
    "/SHAK [\n"
    "  16#428a2f98 16#71374491 16#b5c0fbcf 16#e9b5dba5 16#3956c25b 16#59f111f1 16#923f82a4 16#ab1c5ed5\n"
    "  16#d807aa98 16#12835b01 16#243185be 16#550c7dc3 16#72be5d74 16#80deb1fe 16#9bdc06a7 16#c19bf174\n"
    "  16#e49b69c1 16#efbe4786 16#0fc19dc6 16#240ca1cc 16#2de92c6f 16#4a7484aa 16#5cb0a9dc 16#76f988da\n"
    "  16#983e5152 16#a831c66d 16#b00327c8 16#bf597fc7 16#c6e00bf3 16#d5a79147 16#06ca6351 16#14292967\n"
    "  16#27b70a85 16#2e1b2138 16#4d2c6dfc 16#53380d13 16#650a7354 16#766a0abb 16#81c2c92e 16#92722c85\n"
    "  16#a2bfe8a1 16#a81a664b 16#c24b8b70 16#c76c51a3 16#d192e819 16#d6990624 16#f40e3585 16#106aa070\n"
    "  16#19a4c116 16#1e376c08 16#2748774c 16#34b0bcb5 16#391c0cb3 16#4ed8aa4a 16#5b9cca4f 16#682e6ff3\n"
    "  16#748f82ee 16#78a5636f 16#84c87814 16#8cc70208 16#90befffa 16#a4506ceb 16#bef9a3f7 16#c67178f2\n"
    "] def\n"
    "/SHAW 64 array def\n"
    "/shaH 8 array def\n"
    "/shaBuf 64 string def\n"
    "/shaBufLen 0 def\n"
    "/shaTotalLo 0 def\n"
    "/shaTotalHi 0 def\n"
    "\n"
    "/shaInit {\n"
    "  shaH 0 16#6a09e667 put shaH 1 16#bb67ae85 put\n"
    "  shaH 2 16#3c6ef372 put shaH 3 16#a54ff53a put\n"
    "  shaH 4 16#510e527f put shaH 5 16#9b05688c put\n"
    "  shaH 6 16#1f83d9ab put shaH 7 16#5be0cd19 put\n"
    "  /shaBufLen 0 def /shaTotalLo 0 def /shaTotalHi 0 def\n"
    "} bind def\n"
    "\n"
    "/shaBlock {\n"
    "  30 dict begin\n"
    "  /sb exch def\n"
    "  0 1 15 {\n"
    "    /i exch def /j i 4 mul def\n"
    "    /v sb j get 24 bitshift\n"
    "       sb j 1 add get 16 bitshift or\n"
    "       sb j 2 add get 8 bitshift or\n"
    "       sb j 3 add get or M32 and def\n"
    "    SHAW i v put\n"
    "  } for\n"
    "  16 1 63 {\n"
    "    /i exch def\n"
    "    /x SHAW i 15 sub get def\n"
    "    /s0 x 7 rotr x 18 rotr xor x -3 bitshift xor M32 and def\n"
    "    /x SHAW i 2 sub get def\n"
    "    /s1 x 17 rotr x 19 rotr xor x -10 bitshift xor M32 and def\n"
    "    /v SHAW i 16 sub get s0 add32 SHAW i 7 sub get add32 s1 add32 M32 and def\n"
    "    SHAW i v put\n"
    "  } for\n"
    "  /a shaH 0 get def /b shaH 1 get def /c shaH 2 get def /d shaH 3 get def\n"
    "  /e shaH 4 get def /f shaH 5 get def /g shaH 6 get def /h shaH 7 get def\n"
    "  0 1 63 {\n"
    "    /i exch def\n"
    "    /S1 e 6 rotr e 11 rotr xor e 25 rotr xor M32 and def\n"
    "    /ch e f and e not M32 and g and xor M32 and def\n"
    "    /t1 h S1 add32 ch add32 SHAK i get add32 SHAW i get add32 M32 and def\n"
    "    /S0 a 2 rotr a 13 rotr xor a 22 rotr xor M32 and def\n"
    "    /maj a b and a c and xor b c and xor M32 and def\n"
    "    /t2 S0 maj add32 M32 and def\n"
    "    /h g def /g f def /f e def /e d t1 add32 M32 and def\n"
    "    /d c def /c b def /b a def /a t1 t2 add32 M32 and def\n"
    "  } for\n"
    "  shaH 0 shaH 0 get a add32 M32 and put\n"
    "  shaH 1 shaH 1 get b add32 M32 and put\n"
    "  shaH 2 shaH 2 get c add32 M32 and put\n"
    "  shaH 3 shaH 3 get d add32 M32 and put\n"
    "  shaH 4 shaH 4 get e add32 M32 and put\n"
    "  shaH 5 shaH 5 get f add32 M32 and put\n"
    "  shaH 6 shaH 6 get g add32 M32 and put\n"
    "  shaH 7 shaH 7 get h add32 M32 and put\n"
    "  end\n"
    "} bind def\n"
    "\n"
    "/shaRawByte {\n"
    "  shaBuf shaBufLen 3 -1 roll put\n"
    "  /shaBufLen shaBufLen 1 add def\n"
    "  shaBufLen 64 eq { shaBuf shaBlock /shaBufLen 0 def } if\n"
    "} bind def\n"
    "/shaByte {\n"
    "  shaRawByte\n"
    "  /shaTotalLo shaTotalLo 1 add def\n"
    "  shaTotalLo 16#20000000 eq {\n"
    "    /shaTotalLo 0 def /shaTotalHi shaTotalHi 1 add32 def\n"
    "  } if\n"
    "} bind def\n"
    "/shaString { { shaByte } forall } bind def\n"
    "/shaFinal {\n"
    "  20 dict begin\n"
    "  /origHi shaTotalHi def /origLo shaTotalLo def\n"
    "  128 shaRawByte\n"
    "  { shaBufLen 56 eq { exit } if 0 shaRawByte } loop\n"
    "  /bitHi origHi def /bitLo origLo 3 bitshift M32 and def\n"
    "  bitHi -24 bitshift 255 and shaRawByte\n"
    "  bitHi -16 bitshift 255 and shaRawByte\n"
    "  bitHi -8 bitshift 255 and shaRawByte\n"
    "  bitHi 255 and shaRawByte\n"
    "  bitLo -24 bitshift 255 and shaRawByte\n"
    "  bitLo -16 bitshift 255 and shaRawByte\n"
    "  bitLo -8 bitshift 255 and shaRawByte\n"
    "  bitLo 255 and shaRawByte\n"
    "  /dg 32 string def\n"
    "  0 1 7 {\n"
    "    /i exch def /v shaH i get def /j i 4 mul def\n"
    "    dg j     v -24 bitshift 255 and put\n"
    "    dg j 1 add v -16 bitshift 255 and put\n"
    "    dg j 2 add v -8 bitshift 255 and put\n"
    "    dg j 3 add v 255 and put\n"
    "  } for\n"
    "  dg end\n"
    "} bind def\n"
    "\n"
    "/hIpad 64 string def /hOpad 64 string def\n"
    "/hmacPrepare {\n"
    "  10 dict begin /hk exch def\n"
    "  hk length 64 gt { shaInit hk shaString shaFinal /hk exch def } if\n"
    "  0 1 63 {\n"
    "    /i exch def /kb i hk length lt { hk i get } { 0 } ifelse def\n"
    "    hIpad i kb 16#36 xor put hOpad i kb 16#5c xor put\n"
    "  } for\n"
    "  end\n"
    "} bind def\n"
    "/hmacStart { shaInit hIpad shaString } bind def\n"
    "/hmacFinish {\n"
    "  /hin shaFinal def\n"
    "  shaInit hOpad shaString hin shaString shaFinal\n"
    "} bind def\n"
    "\n"
    "/pbkdf2block {\n"
    "  15 dict begin\n"
    "  /pbIter exch def /pbIndex exch def /pbSalt exch def\n"
    "  /ib 4 string def\n"
    "  ib 0 pbIndex -24 bitshift 255 and put\n"
    "  ib 1 pbIndex -16 bitshift 255 and put\n"
    "  ib 2 pbIndex -8 bitshift 255 and put\n"
    "  ib 3 pbIndex 255 and put\n"
    "  hmacStart pbSalt shaString ib shaString hmacFinish /U exch def\n"
    "  /T 32 string def T 0 U putinterval\n"
    "  2 1 pbIter {\n"
    "    pop hmacStart U shaString hmacFinish /U exch def\n"
    "    0 1 31 { /q exch def T q T q get U q get xor put } for\n"
    "  } for\n"
    "  T end\n"
    "} bind def\n"
    "\n"
    "% AES-256\n"
    "/AESSBox <\n"
    "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0\n"
    "b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275\n"
    "09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cf\n"
    "d0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2\n"
    "cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdb\n"
    "e0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08\n"
    "ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9e\n"
    "e1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16\n"
    "> def\n"
    "/AESShift <00050a0f04090e03080d02070c01060b> def\n"
    "/AESRcon <01020408102040801b36> def\n"
    "/aesRK 240 string def\n"
    "\n"
    "/aesExpand {\n"
    "  25 dict begin /key exch def\n"
    "  aesRK 0 key putinterval\n"
    "  /bytes 32 def /rci 0 def /tmp 4 string def\n"
    "  {\n"
    "    bytes 240 ge { exit } if\n"
    "    0 1 3 { /i exch def tmp i aesRK bytes 4 sub i add get put } for\n"
    "    bytes 32 mod 0 eq {\n"
    "      /t tmp 0 get def\n"
    "      tmp 0 AESSBox tmp 1 get get put\n"
    "      tmp 1 AESSBox tmp 2 get get put\n"
    "      tmp 2 AESSBox tmp 3 get get put\n"
    "      tmp 3 AESSBox t get put\n"
    "      tmp 0 tmp 0 get AESRcon rci get xor put\n"
    "      /rci rci 1 add def\n"
    "    } {\n"
    "      bytes 32 mod 16 eq {\n"
    "        0 1 3 { /i exch def tmp i AESSBox tmp i get get put } for\n"
    "      } if\n"
    "    } ifelse\n"
    "    0 1 3 {\n"
    "      /i exch def /v aesRK bytes 32 sub get tmp i get xor def\n"
    "      aesRK bytes v put /bytes bytes 1 add def\n"
    "    } for\n"
    "  } loop\n"
    "  end\n"
    "} bind def\n"
    "\n"
    "/aesXtime {\n"
    "  /xb exch def\n"
    "  xb 128 and 0 ne { xb 1 bitshift 16#1b xor } { xb 1 bitshift } ifelse 255 and\n"
    "} bind def\n"
    "\n"
    "/aesEncryptBlock {\n"
    "  35 dict begin /inp exch def\n"
    "  /st 16 string def st 0 inp putinterval\n"
    "  0 1 15 { /i exch def st i st i get aesRK i get xor put } for\n"
    "  1 1 13 {\n"
    "    /rnd exch def\n"
    "    0 1 15 { /i exch def st i AESSBox st i get get put } for\n"
    "    /tt 16 string def\n"
    "    0 1 15 { /i exch def tt i st AESShift i get get put } for\n"
    "    /st tt def\n"
    "    0 1 3 {\n"
    "      /c exch def /j c 4 mul def\n"
    "      /a0 st j get def /a1 st j 1 add get def /a2 st j 2 add get def /a3 st j 3 add get def\n"
    "      /mx a0 a1 xor a2 xor a3 xor def /u a0 def\n"
    "      st j     a0 mx xor a0 a1 xor aesXtime xor 255 and put\n"
    "      st j 1 add a1 mx xor a1 a2 xor aesXtime xor 255 and put\n"
    "      st j 2 add a2 mx xor a2 a3 xor aesXtime xor 255 and put\n"
    "      st j 3 add a3 mx xor a3 u xor aesXtime xor 255 and put\n"
    "    } for\n"
    "    /off rnd 16 mul def\n"
    "    0 1 15 { /i exch def st i st i get aesRK off i add get xor put } for\n"
    "  } for\n"
    "  0 1 15 { /i exch def st i AESSBox st i get get put } for\n"
    "  /tt 16 string def\n"
    "  0 1 15 { /i exch def tt i st AESShift i get get put } for\n"
    "  /st tt def /off 224 def\n"
    "  0 1 15 { /i exch def st i st i get aesRK off i add get xor put } for\n"
    "  st end\n"
    "} bind def\n"
    "\n"
    "/incCounter {\n"
    "  5 dict begin /ctr exch def\n"
    "  15 -1 0 {\n"
    "    /i exch def /v ctr i get 1 add def\n"
    "    ctr i v 255 and put v 256 lt { exit } if\n"
    "  } for\n"
    "  end\n"
    "} bind def\n"
    "\n";

static const char PS_ERROR_RENDERER[] =
    "% Minimal error page for an authentication failure.\n"
    "/authenticationFailed {\n"
    "  gsave initgraphics 0 setgray\n"
    "  /Courier-Bold findfont 12 scalefont setfont\n"
    "  /psenMessage wrongPasswordMessage def\n"
    "  clippath pathbbox\n"
    "  /psenTop exch def /psenRight exch def\n"
    "  /psenBottom exch def /psenLeft exch def\n"
    "  psenLeft psenRight add 2 div\n"
    "  psenMessage stringwidth pop 2 div sub\n"
    "  psenBottom psenTop add 2 div moveto\n"
    "  psenMessage show grestore showpage\n"
    "} bind def\n"
    "\n";

static const char PS_POSTSCRIPT_EXECUTOR[] =
    "% PostScript executor: exposes decrypted bytes as one reusable file.\n"
    "/psenChunkIndex 0 def /counter 0 def /ks 0 def /ksPos 0 def\n"
    "/decryptSource {\n"
    "  psenChunkIndex cipherChunks length lt {\n"
    "    /encChunk cipherChunks psenChunkIndex get def\n"
    "    /plainChunk encChunk length string def\n"
    "    0 1 encChunk length 1 sub {\n"
    "      /byteIndex exch def\n"
    "      ksPos 16 ge {\n"
    "        counter aesEncryptBlock /ks exch def\n"
    "        counter incCounter /ksPos 0 def\n"
    "      } if\n"
    "      /cipherByte encChunk byteIndex get def\n"
    "      plainChunk byteIndex cipherByte ks ksPos get xor put\n"
    "      /ksPos ksPos 1 add def\n"
    "    } for\n"
    "    /psenChunkIndex psenChunkIndex 1 add def\n"
    "    plainChunk\n"
    "  } {\n"
    "    ()\n"
    "  } ifelse\n"
    "} bind def\n"
    "\n";

static const char PS_RUNTIME_AUTHENTICATE[] =
    "psenScratchNames { currentdict exch undef } forall\n"
    "currentdict /psenScratchNames undef\n"
    "\n"
    "% ---- Password gate and key derivation ----\n"
    "/authenticationOK true def\n"
    "password <7365637265745f70617373776f7264> eq {\n"
    "  authenticationFailed\n"
    "  /authenticationOK false def\n"
    "} {\n"
    "  password hmacPrepare\n"
    "  /masterKey salt 1 iterations pbkdf2block def\n"
    "  masterKey hmacPrepare\n"
    "  hmacStart (psencrypt-v2/aes-256-ctr) shaString hmacFinish /aesKey exch def\n"
    "  hmacStart (psencrypt-v2/hmac-sha-256) shaString hmacFinish /macKey exch def\n"
    "\n"
    "  /iterBytes 4 string def\n"
    "  iterBytes 0 iterations -24 bitshift 255 and put\n"
    "  iterBytes 1 iterations -16 bitshift 255 and put\n"
    "  iterBytes 2 iterations -8 bitshift 255 and put\n"
    "  iterBytes 3 iterations 255 and put\n"
    "  macKey hmacPrepare hmacStart salt shaString iv shaString iterBytes shaString\n"
    "  cipherChunks { shaString } forall\n"
    "  hmacFinish expectedTag eq not {\n"
    "    authenticationFailed\n"
    "    /authenticationOK false def\n"
    "  } if\n"
    "} ifelse\n"
    "\n"
    "authenticationOK {\n"
    "% ---- AES-CTR setup ----\n"
    "aesKey aesExpand\n"
    "/counter 16 string def counter 0 iv putinterval\n"
    "/ks 16 string def /ksPos 16 def\n";

static const char PS_POSTSCRIPT_DRIVER[] =
    "% ---- Decrypt and execute PostScript ----\n"
    "/decryptSource load /ReusableStreamDecode filter cvx exec\n"
    "} if\n";

static int ascii_case_equal(const char *a, const char *b) {
    while (*a && *b) {
        unsigned char ca = (unsigned char)*a++;
        unsigned char cb = (unsigned char)*b++;
        if (ca >= 'A' && ca <= 'Z') ca = (unsigned char)(ca - 'A' + 'a');
        if (cb >= 'A' && cb <= 'Z') cb = (unsigned char)(cb - 'A' + 'a');
        if (ca != cb) return 0;
    }
    return *a == '\0' && *b == '\0';
}

static const char *path_extension(const char *path) {
    const char *slash = strrchr(path, '/');
    const char *base = slash ? slash + 1 : path;
    const char *dot = strrchr(base, '.');
    return dot && dot != base ? dot : NULL;
}

static int has_postscript_extension(const char *path) {
    const char *extension = path_extension(path);
    return extension &&
           (ascii_case_equal(extension, ".ps") ||
            ascii_case_equal(extension, ".eps"));
}

static int starts_with_postscript_magic(FILE *in) {
    unsigned char magic[4];
    size_t count = fread(magic, 1, sizeof magic, in);
    if (ferror(in)) return -1;
    if (fseek(in, 0, SEEK_SET) != 0) return -1;
    return count == sizeof magic && memcmp(magic, "%!PS", sizeof magic) == 0;
}

static int write_hex(FILE *out, const unsigned char *p, size_t n) {
    static const char h[] = "0123456789abcdef";
    for (size_t i = 0; i < n; ++i) {
        if (fputc(h[p[i] >> 4], out) == EOF ||
            fputc(h[p[i] & 15], out) == EOF) {
            return 0;
        }
    }
    return 1;
}

static int write_ps_header(FILE *out, const unsigned char salt[SALT_LEN],
                           const unsigned char iv[IV_LEN], int iterations) {
    if (fputs("%!PS-Adobe-3.0\n", out) == EOF ||
        fputs("%%Creator: iPS2PDF\n", out) == EOF ||
        fputs("%%Pages: (atend)\n", out) == EOF ||
        fputs("%%LanguageLevel: 3\n", out) == EOF ||
        fputs("%%PSEncryptMode: PostScript\n", out) == EOF ||
        fputs("%%EndComments\n", out) == EOF ||
        fputs("/password (" PASSWORD_PLACEHOLDER ") def\n", out) == EOF ||
        fprintf(out, "/iterations %d def\n", iterations) < 0 ||
        fputs("/wrongPasswordMessage <", out) == EOF ||
        !write_hex(out, (const unsigned char *)WRONG_PASSWORD_MESSAGE,
                   strlen(WRONG_PASSWORD_MESSAGE)) ||
        fputs("> def\n/salt <", out) == EOF ||
        !write_hex(out, salt, SALT_LEN) ||
        fputs("> def\n/iv <", out) == EOF ||
        !write_hex(out, iv, IV_LEN) ||
        fputs("> def\n/cipherChunks [\n", out) == EOF) {
        return 0;
    }
    return 1;
}

int psencrypt_validate_password(const char *password) {
    if (!password) return PSENCRYPT_INVALID_ARGUMENT;
    size_t length = strlen(password);
    if (length == 0) return PSENCRYPT_PASSWORD_EMPTY;
    if (length > MAX_PASSWORD_LEN) return PSENCRYPT_PASSWORD_TOO_LONG;
    for (size_t index = 0; index < length; ++index) {
        unsigned char character = (unsigned char)password[index];
        if (character < 0x20 || character > 0x7e ||
            character == '(' || character == ')' || character == '\\') {
            return PSENCRYPT_PASSWORD_UNSUPPORTED_CHARACTER;
        }
    }
    if (strcmp(password, PASSWORD_PLACEHOLDER) == 0) {
        return PSENCRYPT_PASSWORD_RESERVED;
    }
    return PSENCRYPT_SUCCESS;
}

int psencrypt_encrypt_postscript(const char *input_path,
                                 const char *output_path,
                                 const char *password) {
    int result = PSENCRYPT_INVALID_ARGUMENT;
    FILE *in = NULL;
    FILE *out = NULL;
    PS_CIPHER_CTX cipher = NULL;
    PS_HMAC_CTX hmac = NULL;
    unsigned char salt[SALT_LEN] = {0};
    unsigned char iv[IV_LEN] = {0};
    unsigned char master[KEY_LEN] = {0};
    unsigned char aes_key[KEY_LEN] = {0};
    unsigned char mac_key[KEY_LEN] = {0};
    unsigned char tag[TAG_LEN] = {0};
    int output_created = 0;

    if (!input_path || !output_path) goto cleanup;
    result = psencrypt_validate_password(password);
    if (result != PSENCRYPT_SUCCESS) goto cleanup;

    in = fopen(input_path, "rb");
    if (!in) {
        result = PSENCRYPT_INPUT_OPEN_FAILED;
        goto cleanup;
    }

    if (!has_postscript_extension(input_path)) {
        int magic = starts_with_postscript_magic(in);
        if (magic < 0) {
            result = PSENCRYPT_READ_FAILED;
            goto cleanup;
        }
        if (!magic) {
            result = PSENCRYPT_INPUT_NOT_POSTSCRIPT;
            goto cleanup;
        }
    }

    if (!ps_random(salt, sizeof salt) || !ps_random(iv, sizeof iv)) {
        result = PSENCRYPT_RANDOM_FAILED;
        goto cleanup;
    }
    if (!ps_pbkdf2(password, salt, sizeof salt, DEFAULT_ITERATIONS, master)) {
        result = PSENCRYPT_KEY_DERIVATION_FAILED;
        goto cleanup;
    }
    if (!ps_derive_key(master, AES_KEY_LABEL, sizeof AES_KEY_LABEL - 1, aes_key) ||
        !ps_derive_key(master, MAC_KEY_LABEL, sizeof MAC_KEY_LABEL - 1, mac_key)) {
        result = PSENCRYPT_KEY_DERIVATION_FAILED;
        goto cleanup;
    }

    errno = 0;
    out = fopen(output_path, "wbx");
    if (!out) {
        result = errno == EEXIST ? PSENCRYPT_OUTPUT_EXISTS
                                : PSENCRYPT_OUTPUT_OPEN_FAILED;
        goto cleanup;
    }
    output_created = 1;

    if (!write_ps_header(out, salt, iv, DEFAULT_ITERATIONS)) {
        result = PSENCRYPT_WRITE_FAILED;
        goto cleanup;
    }

    cipher = ps_cipher_new(aes_key, iv);
    hmac = ps_hmac_new(mac_key, sizeof mac_key);
    if (!cipher || !hmac) {
        result = PSENCRYPT_CRYPTO_FAILED;
        goto cleanup;
    }

    unsigned char iteration_bytes[4] = {
        (unsigned char)((uint32_t)DEFAULT_ITERATIONS >> 24),
        (unsigned char)((uint32_t)DEFAULT_ITERATIONS >> 16),
        (unsigned char)((uint32_t)DEFAULT_ITERATIONS >> 8),
        (unsigned char)(uint32_t)DEFAULT_ITERATIONS
    };
    if (!ps_hmac_update(hmac, salt, sizeof salt) ||
        !ps_hmac_update(hmac, iv, sizeof iv) ||
        !ps_hmac_update(hmac, iteration_bytes, sizeof iteration_bytes)) {
        result = PSENCRYPT_CRYPTO_FAILED;
        goto cleanup;
    }

    unsigned char input_buffer[IO_CHUNK];
    unsigned char output_buffer[IO_CHUNK + kCCBlockSizeAES128];
    unsigned char hex_buffer[HEX_CHUNK];
    size_t hex_length = 0;

    for (;;) {
        size_t read_length = fread(input_buffer, 1, sizeof input_buffer, in);
        if (read_length == 0) {
            if (ferror(in)) {
                result = PSENCRYPT_READ_FAILED;
                goto cleanup;
            }
            break;
        }

        size_t output_length = 0;
        if (!ps_cipher_update(cipher, input_buffer, read_length,
                              output_buffer, sizeof output_buffer,
                              &output_length) ||
            !ps_hmac_update(hmac, output_buffer, output_length)) {
            result = PSENCRYPT_CRYPTO_FAILED;
            goto cleanup;
        }

        size_t position = 0;
        while (position < output_length) {
            size_t take = sizeof hex_buffer - hex_length;
            if (take > output_length - position) take = output_length - position;
            memcpy(hex_buffer + hex_length, output_buffer + position, take);
            hex_length += take;
            position += take;
            if (hex_length == sizeof hex_buffer) {
                if (fputc('<', out) == EOF ||
                    !write_hex(out, hex_buffer, hex_length) ||
                    fputs(">\n", out) == EOF) {
                    result = PSENCRYPT_WRITE_FAILED;
                    goto cleanup;
                }
                hex_length = 0;
            }
        }
    }

    size_t final_length = 0;
    if (!ps_cipher_final(cipher, output_buffer, sizeof output_buffer,
                         &final_length) ||
        (final_length > 0 &&
         !ps_hmac_update(hmac, output_buffer, final_length))) {
        result = PSENCRYPT_CRYPTO_FAILED;
        goto cleanup;
    }
    if (final_length > 0) {
        if (hex_length + final_length > sizeof hex_buffer) {
            result = PSENCRYPT_CRYPTO_FAILED;
            goto cleanup;
        }
        memcpy(hex_buffer + hex_length, output_buffer, final_length);
        hex_length += final_length;
    }
    if (hex_length > 0 &&
        (fputc('<', out) == EOF ||
         !write_hex(out, hex_buffer, hex_length) ||
         fputs(">\n", out) == EOF)) {
        result = PSENCRYPT_WRITE_FAILED;
        goto cleanup;
    }
    if (fputs("] def\n", out) == EOF) {
        result = PSENCRYPT_WRITE_FAILED;
        goto cleanup;
    }

    if (!ps_hmac_final(hmac, tag)) {
        result = PSENCRYPT_CRYPTO_FAILED;
        goto cleanup;
    }
    if (fputs("/expectedTag <", out) == EOF ||
        !write_hex(out, tag, TAG_LEN) ||
        fputs("> def\n", out) == EOF ||
        fputs(PS_RUNTIME_PREFIX, out) == EOF ||
        fputs(PS_ERROR_RENDERER, out) == EOF ||
        fputs(PS_POSTSCRIPT_EXECUTOR, out) == EOF ||
        fputs(PS_RUNTIME_AUTHENTICATE, out) == EOF ||
        fputs(PS_POSTSCRIPT_DRIVER, out) == EOF ||
        fputs("\n%%Trailer\n%%EOF\n", out) == EOF) {
        result = PSENCRYPT_WRITE_FAILED;
        goto cleanup;
    }

    if (fclose(in) != 0) {
        in = NULL;
        result = PSENCRYPT_READ_FAILED;
        goto cleanup;
    }
    in = NULL;
    if (fclose(out) != 0) {
        out = NULL;
        result = PSENCRYPT_WRITE_FAILED;
        goto cleanup;
    }
    out = NULL;
    result = PSENCRYPT_SUCCESS;

cleanup:
    ps_cipher_free(cipher);
    ps_hmac_free(hmac);
    if (in) fclose(in);
    if (out) fclose(out);
    if (result != PSENCRYPT_SUCCESS && output_created) remove(output_path);
    ps_cleanse(master, sizeof master);
    ps_cleanse(aes_key, sizeof aes_key);
    ps_cleanse(mac_key, sizeof mac_key);
    ps_cleanse(tag, sizeof tag);
    return result;
}
