/*
 * Interoperability check between libolm, the reference Olm implementation, and
 * this library, for Olm session version 1 (E2EE_DESIGN.md, decision D10).
 *
 * Both directions run on every call, with fresh random keys:
 *   A. libolm starts a session and sends the first messages. This library
 *      receives them and replies, and libolm decrypts the replies.
 *   B. This library starts a session and sends the first messages. libolm
 *      receives them and replies, and this library decrypts the replies.
 * In both directions the session ids must match on the two ends.
 *
 * libolm takes public keys and messages as unpadded base64 text, so this file
 * encodes and decodes them. This library takes and returns raw bytes.
 *
 * Build and run on Linux (libolm-dev provides olm/olm.h and -lolm):
 *   cc -std=c11 -Wall -Wextra -Werror -I include tests/interop/libolm_interop.c \
 *      target/release/libe2ee_olm.a -lolm -lpthread -ldl -lm -o libolm_interop
 *   ./libolm_interop
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>

#include <olm/olm.h>

#include "e2ee_olm.h"

static int checks = 0;
static int failures = 0;

#define CHECK(cond)                                                              \
    do {                                                                         \
        checks++;                                                                \
        if (!(cond)) {                                                           \
            failures++;                                                          \
            fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                        \
    } while (0)

/* Room for any message in these tests, as raw bytes or as base64 text. */
#define MSG_CAP 1024

static const char B64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/* Unpadded standard base64 of len bytes, NUL-terminated. out needs 4 * len / 3 + 2 bytes. */
static size_t b64_encode(const uint8_t *in, size_t len, char *out) {
    size_t n = 0;
    for (size_t i = 0; i < len; i += 3) {
        uint32_t b = (uint32_t)in[i] << 16;
        size_t rest = len - i;
        if (rest > 1) {
            b |= (uint32_t)in[i + 1] << 8;
        }
        if (rest > 2) {
            b |= (uint32_t)in[i + 2];
        }
        out[n++] = B64[(b >> 18) & 63];
        out[n++] = B64[(b >> 12) & 63];
        if (rest > 1) {
            out[n++] = B64[(b >> 6) & 63];
        }
        if (rest > 2) {
            out[n++] = B64[b & 63];
        }
    }
    out[n] = '\0';
    return n;
}

/* Decodes unpadded base64 into out. Returns the byte count, or -1 for bad input. */
static long b64_decode(const char *in, size_t len, uint8_t *out, size_t cap) {
    uint32_t acc = 0;
    int bits = 0;
    size_t n = 0;
    for (size_t i = 0; i < len; i++) {
        const char *hit = (in[i] == '\0') ? NULL : strchr(B64, in[i]);
        if (hit == NULL) {
            return -1;
        }
        acc = (acc << 6) | (uint32_t)(hit - B64);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (n >= cap) {
                return -1;
            }
            out[n++] = (uint8_t)((acc >> bits) & 0xff);
        }
    }
    return (long)n;
}

/* Copies the quoted value that follows key (for example "\"ed25519\":\"") into out. */
static long json_value(const char *json, const char *key, char *out, size_t cap) {
    const char *p = strstr(json, key);
    if (p == NULL) {
        return -1;
    }
    p += strlen(key);
    const char *end = strchr(p, '"');
    if (end == NULL) {
        return -1;
    }
    size_t n = (size_t)(end - p);
    if (n + 1 > cap) {
        return -1;
    }
    memcpy(out, p, n);
    out[n] = '\0';
    return (long)n;
}

/* The first one-time key in {"curve25519":{"<key id>":"<base64>"}}. */
static long first_one_time_key(const char *json, char *out, size_t cap) {
    const char *p = strstr(json, "\"curve25519\":{");
    if (p == NULL) {
        return -1;
    }
    p = strstr(p, "\":\"");
    if (p == NULL) {
        return -1;
    }
    return json_value(p, "\":\"", out, cap);
}

static void random_bytes(uint8_t *out, size_t len) {
    while (len > 0) {
        ssize_t got = getrandom(out, len, 0);
        if (got <= 0) {
            perror("getrandom");
            exit(2);
        }
        out += got;
        len -= (size_t)got;
    }
}

/* Reads the account's Curve25519 identity key in raw and base64 form. */
static void libolm_identity(OlmAccount *acc, uint8_t raw[32], char b64[64]) {
    size_t len = olm_account_identity_keys_length(acc);
    char *json = malloc(len + 1);
    CHECK(olm_account_identity_keys(acc, json, len) != (size_t)-1);
    json[len] = '\0';
    long n = json_value(json, "\"curve25519\":\"", b64, 64);
    CHECK(n == 43);
    CHECK(b64_decode(b64, (size_t)n, raw, 32) == 32);
    free(json);
}

/* Creates one unpublished one-time key and reads it in raw and base64 form. */
static void libolm_one_time_key(OlmAccount *acc, uint8_t raw[32], char b64[64]) {
    size_t rlen = olm_account_generate_one_time_keys_random_length(acc, 1);
    uint8_t *rnd = malloc(rlen);
    random_bytes(rnd, rlen);
    CHECK(olm_account_generate_one_time_keys(acc, 1, rnd, rlen) != (size_t)-1);
    free(rnd);
    size_t len = olm_account_one_time_keys_length(acc);
    char *json = malloc(len + 1);
    CHECK(olm_account_one_time_keys(acc, json, len) != (size_t)-1);
    json[len] = '\0';
    long n = first_one_time_key(json, b64, 64);
    CHECK(n == 43);
    CHECK(b64_decode(b64, (size_t)n, raw, 32) == 32);
    free(json);
}

static OlmAccount *new_libolm_account(void) {
    OlmAccount *acc = olm_account(malloc(olm_account_size()));
    size_t rlen = olm_create_account_random_length(acc);
    uint8_t *rnd = malloc(rlen);
    random_bytes(rnd, rlen);
    CHECK(olm_create_account(acc, rnd, rlen) != (size_t)-1);
    free(rnd);
    return acc;
}

static OlmSession *new_libolm_session(void) {
    return olm_session(malloc(olm_session_size()));
}

/*
 * Encrypts text with libolm. libolm returns base64 text, which is NUL-terminated
 * here. Writes the Olm message type and the text length. Free the result.
 */
static char *libolm_encrypt(OlmSession *s, const char *text, size_t *type, size_t *len) {
    size_t text_len = strlen(text);
    *type = olm_encrypt_message_type(s);
    size_t out_len = olm_encrypt_message_length(s, text_len);
    size_t rlen = olm_encrypt_random_length(s);
    uint8_t *rnd = malloc(rlen);
    random_bytes(rnd, rlen);
    char *out = malloc(out_len + 1);
    *len = olm_encrypt(s, text, text_len, rnd, rlen, out, out_len);
    free(rnd);
    CHECK(*len != (size_t)-1);
    if (*len == (size_t)-1) {
        *len = 0;
    }
    out[*len] = '\0';
    return out;
}

/*
 * Decrypts libolm's base64 text with libolm. Returns the plaintext length, or -1.
 * libolm changes its input, so each call works on a copy.
 */
static long libolm_decrypt(OlmSession *s, size_t type, const char *text, size_t len,
                           char *out, size_t cap) {
    char *work = malloc(len + 1);
    memcpy(work, text, len);
    work[len] = '\0';
    size_t max = olm_decrypt_max_plaintext_length(s, type, work, len);
    free(work);
    if (max == (size_t)-1) {
        return -1;
    }
    work = malloc(len + 1);
    memcpy(work, text, len);
    work[len] = '\0';
    uint8_t *plain = malloc(max);
    size_t got = olm_decrypt(s, type, work, len, plain, max);
    free(work);
    long result = -1;
    if (got != (size_t)-1 && got + 1 <= cap) {
        memcpy(out, plain, got);
        out[got] = '\0';
        result = (long)got;
    }
    free(plain);
    return result;
}

/* Encrypts text with this library. Returns the raw message length, or -1. Free with e2ee_bytes_free. */
static long ours_encrypt(E2eeSession *s, const char *text, size_t *type, uint8_t **out) {
    size_t len = 0;
    if (e2ee_session_encrypt(s, (const uint8_t *)text, strlen(text), type, out, &len) != E2EE_OK) {
        return -1;
    }
    return (long)len;
}

/* Decrypts a raw message with this library. Returns the plaintext length, or -1. */
static long ours_decrypt(E2eeSession *s, size_t type, const uint8_t *msg, size_t len,
                         char *out, size_t cap) {
    uint8_t *plain = NULL;
    size_t plain_len = 0;
    if (e2ee_session_decrypt(s, type, msg, len, &plain, &plain_len) != E2EE_OK) {
        return -1;
    }
    long result = -1;
    if (plain_len + 1 <= cap) {
        memcpy(out, plain, plain_len);
        out[plain_len] = '\0';
        result = (long)plain_len;
    }
    e2ee_bytes_free(plain, plain_len);
    return result;
}

/* Encodes this library's raw message as base64 text for libolm. Returns the text length. */
static size_t text_for_libolm(const uint8_t *raw, size_t len, char *text) {
    CHECK(4 * ((len + 2) / 3) + 1 <= MSG_CAP);
    return b64_encode(raw, len, text);
}

/* Checks that this library's session id matches libolm's. */
static void check_session_ids(OlmSession *lib, E2eeSession *ours) {
    uint8_t *our_id = NULL;
    size_t our_len = 0;
    if (e2ee_session_id(ours, &our_id, &our_len) != E2EE_OK) {
        CHECK(0);
        return;
    }
    size_t lib_len = olm_session_id_length(lib);
    char *lib_id = malloc(lib_len + 1);
    CHECK(olm_session_id(lib, lib_id, lib_len) != (size_t)-1);
    lib_id[lib_len] = '\0';
    CHECK(our_len == lib_len && memcmp(our_id, lib_id, lib_len) == 0);
    free(lib_id);
    e2ee_bytes_free(our_id, our_len);
}

/* Direction A: libolm starts the session, and this library is Bob. */
static void direction_libolm_starts(void) {
    E2eeAccount *bob = e2ee_account_new();
    CHECK(bob != NULL);
    uint8_t bob_curve[32], bob_otk[32];
    CHECK(e2ee_account_curve25519_key(bob, bob_curve) == E2EE_OK);
    CHECK(e2ee_account_generate_one_time_keys(bob, 1) == E2EE_OK);
    size_t otk_count = 0;
    CHECK(e2ee_account_one_time_keys(bob, bob_otk, 1, &otk_count) == E2EE_OK);
    CHECK(otk_count == 1);

    OlmAccount *alice = new_libolm_account();
    uint8_t alice_curve[32];
    char alice_b64[64];
    libolm_identity(alice, alice_curve, alice_b64);

    /* libolm takes Bob's keys as base64 text. */
    char bob_curve_b64[64], bob_otk_b64[64];
    b64_encode(bob_curve, 32, bob_curve_b64);
    b64_encode(bob_otk, 32, bob_otk_b64);
    OlmSession *alice_sess = new_libolm_session();
    size_t srlen = olm_create_outbound_session_random_length(alice_sess);
    uint8_t *srnd = malloc(srlen);
    random_bytes(srnd, srlen);
    CHECK(olm_create_outbound_session(alice_sess, alice, bob_curve_b64, strlen(bob_curve_b64),
                                      bob_otk_b64, strlen(bob_otk_b64), srnd, srlen) != (size_t)-1);
    free(srnd);

    char out[256];
    uint8_t raw[MSG_CAP];

    /* libolm's first message is a pre-key message, which creates Bob's session. */
    size_t t1 = 0, l1 = 0;
    char *m1 = libolm_encrypt(alice_sess, "hello bob", &t1, &l1);
    CHECK(t1 == 0);
    long r1 = b64_decode(m1, l1, raw, sizeof raw);
    CHECK(r1 > 0);
    E2eeSession *bob_sess = NULL;
    uint8_t *pt = NULL;
    size_t pt_len = 0;
    if (r1 > 0) {
        CHECK(e2ee_session_create_inbound(bob, alice_curve, raw, (size_t)r1, &bob_sess, &pt,
                                          &pt_len) == E2EE_OK);
    }
    CHECK(pt_len == 9 && memcmp(pt, "hello bob", 9) == 0);
    e2ee_bytes_free(pt, pt_len);
    if (bob_sess == NULL) {
        /* Without Bob's session the rest of this direction cannot run. */
        free(m1);
        free(alice_sess);
        return;
    }

    /* A second pre-key message from libolm, sent before Bob has replied. */
    size_t t2 = 0, l2 = 0;
    char *m2 = libolm_encrypt(alice_sess, "second", &t2, &l2);
    CHECK(t2 == 0);
    long r2 = b64_decode(m2, l2, raw, sizeof raw);
    CHECK(r2 > 0);
    if (r2 > 0) {
        CHECK(ours_decrypt(bob_sess, t2, raw, (size_t)r2, out, sizeof out) == 6 &&
              strcmp(out, "second") == 0);
    }
    free(m2);

    /* Bob replies with a normal message (type 1), which libolm decrypts. */
    size_t tr = 0;
    uint8_t *reply = NULL;
    long lr = ours_encrypt(bob_sess, "hi alice", &tr, &reply);
    CHECK(lr > 0 && tr == 1);
    if (lr > 0) {
        char reply_b64[MSG_CAP];
        size_t n = text_for_libolm(reply, (size_t)lr, reply_b64);
        CHECK(libolm_decrypt(alice_sess, tr, reply_b64, n, out, sizeof out) == 8 &&
              strcmp(out, "hi alice") == 0);
        e2ee_bytes_free(reply, (size_t)lr);
    }

    /* The ratchet turns over in both directions. */
    for (int i = 0; i < 4; i++) {
        char text[32];
        snprintf(text, sizeof text, "libolm %d", i);
        size_t t = 0, l = 0;
        char *m = libolm_encrypt(alice_sess, text, &t, &l);
        long n = b64_decode(m, l, raw, sizeof raw);
        CHECK(t == 1 && n > 0);
        if (n > 0) {
            CHECK(ours_decrypt(bob_sess, t, raw, (size_t)n, out, sizeof out) == (long)strlen(text) &&
                  strcmp(out, text) == 0);
        }
        free(m);

        snprintf(text, sizeof text, "ours %d", i);
        size_t tb = 0;
        uint8_t *mb = NULL;
        long lb = ours_encrypt(bob_sess, text, &tb, &mb);
        CHECK(lb > 0 && tb == 1);
        if (lb > 0) {
            char b64[MSG_CAP];
            size_t n2 = text_for_libolm(mb, (size_t)lb, b64);
            CHECK(libolm_decrypt(alice_sess, tb, b64, n2, out, sizeof out) == (long)strlen(text) &&
                  strcmp(out, text) == 0);
            e2ee_bytes_free(mb, (size_t)lb);
        }
    }

    check_session_ids(alice_sess, bob_sess);

    free(m1);
    e2ee_session_free(bob_sess);
    e2ee_account_free(bob);
}

/* Direction B: this library starts the session, and libolm is Bob. */
static void direction_ours_starts(void) {
    OlmAccount *bob = new_libolm_account();
    uint8_t bob_curve[32], bob_otk[32];
    char bob_curve_b64[64], bob_otk_b64[64];
    libolm_identity(bob, bob_curve, bob_curve_b64);
    libolm_one_time_key(bob, bob_otk, bob_otk_b64);

    E2eeAccount *alice = e2ee_account_new();
    CHECK(alice != NULL);
    E2eeSession *alice_sess = NULL;
    CHECK(e2ee_session_create_outbound(alice, bob_curve, bob_otk, &alice_sess) == E2EE_OK);
    if (alice_sess == NULL) {
        return;
    }

    char out[256];
    char text_b64[MSG_CAP];
    uint8_t raw[MSG_CAP];

    /* This library's first message is a pre-key message, which creates libolm's session. */
    size_t t1 = 0;
    uint8_t *m1 = NULL;
    long l1 = ours_encrypt(alice_sess, "hello libolm", &t1, &m1);
    CHECK(l1 > 0 && t1 == 0);
    if (l1 <= 0) {
        return;
    }
    size_t m1_len = text_for_libolm(m1, (size_t)l1, text_b64);
    char *work = malloc(m1_len + 1);
    memcpy(work, text_b64, m1_len + 1);
    OlmSession *bob_sess = new_libolm_session();
    CHECK(olm_create_inbound_session(bob_sess, bob, work, m1_len) != (size_t)-1);
    free(work);
    CHECK(libolm_decrypt(bob_sess, t1, text_b64, m1_len, out, sizeof out) == 12 &&
          strcmp(out, "hello libolm") == 0);
    e2ee_bytes_free(m1, (size_t)l1);

    /* A second pre-key message from this library, before libolm replies. */
    size_t t2 = 0;
    uint8_t *m2 = NULL;
    long l2 = ours_encrypt(alice_sess, "second", &t2, &m2);
    CHECK(l2 > 0 && t2 == 0);
    if (l2 > 0) {
        size_t n = text_for_libolm(m2, (size_t)l2, text_b64);
        CHECK(libolm_decrypt(bob_sess, t2, text_b64, n, out, sizeof out) == 6 &&
              strcmp(out, "second") == 0);
        e2ee_bytes_free(m2, (size_t)l2);
    }

    /* libolm replies with a normal message (type 1), which this library decrypts. */
    size_t tr = 0, reply_len = 0;
    char *reply = libolm_encrypt(bob_sess, "hi ours", &tr, &reply_len);
    long rn = b64_decode(reply, reply_len, raw, sizeof raw);
    CHECK(tr == 1 && rn > 0);
    if (rn > 0) {
        CHECK(ours_decrypt(alice_sess, tr, raw, (size_t)rn, out, sizeof out) == 7 &&
              strcmp(out, "hi ours") == 0);
    }
    free(reply);

    /* The ratchet turns over in both directions. */
    for (int i = 0; i < 4; i++) {
        char text[32];
        snprintf(text, sizeof text, "ours %d", i);
        size_t tb = 0;
        uint8_t *mb = NULL;
        long lb = ours_encrypt(alice_sess, text, &tb, &mb);
        CHECK(lb > 0 && tb == 1);
        if (lb > 0) {
            size_t n = text_for_libolm(mb, (size_t)lb, text_b64);
            CHECK(libolm_decrypt(bob_sess, tb, text_b64, n, out, sizeof out) == (long)strlen(text) &&
                  strcmp(out, text) == 0);
            e2ee_bytes_free(mb, (size_t)lb);
        }

        snprintf(text, sizeof text, "libolm %d", i);
        size_t t = 0, l = 0;
        char *m = libolm_encrypt(bob_sess, text, &t, &l);
        long n = b64_decode(m, l, raw, sizeof raw);
        CHECK(t == 1 && n > 0);
        if (n > 0) {
            CHECK(ours_decrypt(alice_sess, t, raw, (size_t)n, out, sizeof out) == (long)strlen(text) &&
                  strcmp(out, text) == 0);
        }
        free(m);
    }

    check_session_ids(bob_sess, alice_sess);

    e2ee_session_free(alice_sess);
    e2ee_account_free(alice);
}

int main(void) {
    uint8_t major = 0, minor = 0, patch = 0;
    olm_get_library_version(&major, &minor, &patch);
    printf("libolm %u.%u.%u\n", (unsigned)major, (unsigned)minor, (unsigned)patch);

    direction_libolm_starts();
    direction_ours_starts();

    if (failures != 0) {
        fprintf(stderr, "libolm interop: %d of %d checks failed\n", failures, checks);
        return 1;
    }
    printf("libolm interop: all %d checks passed\n", checks);
    return 0;
}
