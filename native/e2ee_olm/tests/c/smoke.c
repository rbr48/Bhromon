/*
 * Smoke test for the C interface. It is compiled against the static library, the
 * way the Android and iOS builds will call it. It exits 0 when every check holds.
 *
 *   cc -std=c11 -Wall -Wextra -Werror -I include tests/c/smoke.c \
 *      target/release/libe2ee_olm.a -lpthread -ldl -lm -o smoke && ./smoke
 */
#include <stdio.h>
#include <string.h>

#include "e2ee_olm.h"

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #cond); \
            failures++;                                                    \
        }                                                                  \
    } while (0)

int main(void) {
    CHECK(e2ee_abi_version() == E2EE_ABI_VERSION);

    E2eeAccount *alice = e2ee_account_new();
    E2eeAccount *bob = e2ee_account_new();
    CHECK(alice != NULL);
    CHECK(bob != NULL);
    if (alice == NULL || bob == NULL) {
        return 1;
    }

    uint8_t alice_id[32], bob_id[32], bob_ed[32], bob_otk[32];
    CHECK(e2ee_account_curve25519_key(alice, alice_id) == E2EE_OK);
    CHECK(e2ee_account_curve25519_key(bob, bob_id) == E2EE_OK);
    CHECK(e2ee_account_ed25519_key(bob, bob_ed) == E2EE_OK);

    /* One-time keys: generate, list the unpublished ones, mark them published. */
    CHECK(e2ee_account_generate_one_time_keys(bob, 5) == E2EE_OK);
    size_t otk_count = 0;
    CHECK(e2ee_account_one_time_keys(bob, bob_otk, 1, &otk_count) == E2EE_OK);
    CHECK(otk_count == 1);
    CHECK(e2ee_account_mark_keys_published(bob) == E2EE_OK);
    size_t after_publish = 99;
    CHECK(e2ee_account_one_time_keys(bob, bob_otk, 1, &after_publish) == E2EE_OK);
    CHECK(after_publish == 0);

    /* Bob signs his one-time key. Alice checks it with Bob's Ed25519 key. */
    uint8_t sig[64];
    CHECK(e2ee_account_sign(bob, bob_otk, 32, sig) == E2EE_OK);
    CHECK(e2ee_verify_signature(bob_ed, bob_otk, 32, sig) == E2EE_OK);
    CHECK(e2ee_verify_signature(bob_ed, alice_id, 32, sig) == E2EE_ERR_SIGNATURE);

    /* Fallback key: none at first, one after generation. */
    uint8_t fallback[32];
    size_t has_fallback = 9;
    CHECK(e2ee_account_fallback_key(bob, fallback, &has_fallback) == E2EE_OK);
    CHECK(has_fallback == 0);
    CHECK(e2ee_account_generate_fallback_key(bob) == E2EE_OK);
    CHECK(e2ee_account_fallback_key(bob, fallback, &has_fallback) == E2EE_OK);
    CHECK(has_fallback == 1);

    /* Session round trip: pre-key message, then a reply. */
    E2eeSession *a = NULL;
    CHECK(e2ee_session_create_outbound(alice, bob_id, bob_otk, &a) == E2EE_OK);
    CHECK(a != NULL);

    const char *hello = "hello bob";
    size_t kind = 99;
    uint8_t *prekey = NULL;
    size_t prekey_len = 0;
    CHECK(e2ee_session_encrypt(a, (const uint8_t *)hello, strlen(hello), &kind, &prekey, &prekey_len) == E2EE_OK);
    CHECK(kind == 0);

    E2eeSession *b = NULL;
    uint8_t *pt = NULL;
    size_t pt_len = 0;
    CHECK(e2ee_session_create_inbound(bob, alice_id, prekey, prekey_len, &b, &pt, &pt_len) == E2EE_OK);
    CHECK(pt_len == strlen(hello) && memcmp(pt, hello, pt_len) == 0);
    e2ee_bytes_free(pt, pt_len);

    /* A replayed pre-key message must not decrypt on the session that consumed it. */
    uint8_t *replay = NULL;
    size_t replay_len = 0;
    CHECK(e2ee_session_decrypt(b, 0, prekey, prekey_len, &replay, &replay_len) != E2EE_OK);
    e2ee_bytes_free(prekey, prekey_len);

    const char *reply = "hi alice";
    size_t reply_kind = 99;
    uint8_t *reply_ct = NULL;
    size_t reply_ct_len = 0;
    CHECK(e2ee_session_encrypt(b, (const uint8_t *)reply, strlen(reply), &reply_kind, &reply_ct, &reply_ct_len) == E2EE_OK);
    CHECK(reply_kind == 1);
    uint8_t *reply_pt = NULL;
    size_t reply_pt_len = 0;
    CHECK(e2ee_session_decrypt(a, reply_kind, reply_ct, reply_ct_len, &reply_pt, &reply_pt_len) == E2EE_OK);
    CHECK(reply_pt_len == strlen(reply) && memcmp(reply_pt, reply, reply_pt_len) == 0);
    e2ee_bytes_free(reply_pt, reply_pt_len);
    e2ee_bytes_free(reply_ct, reply_ct_len);

    /* Session pickle: a restored session keeps working, and a wrong key is refused. */
    uint8_t key[32], wrong[32];
    memset(key, 7, sizeof key);
    memset(wrong, 9, sizeof wrong);
    uint8_t *sealed = NULL;
    size_t sealed_len = 0;
    CHECK(e2ee_session_pickle(a, key, &sealed, &sealed_len) == E2EE_OK);
    E2eeSession *refused = NULL;
    CHECK(e2ee_session_from_pickle(sealed, sealed_len, wrong, &refused) == E2EE_ERR_PICKLE);
    CHECK(refused == NULL);
    E2eeSession *restored = NULL;
    CHECK(e2ee_session_from_pickle(sealed, sealed_len, key, &restored) == E2EE_OK);
    e2ee_bytes_free(sealed, sealed_len);

    const char *after = "after restore";
    size_t after_kind = 99;
    uint8_t *after_ct = NULL;
    size_t after_ct_len = 0;
    CHECK(e2ee_session_encrypt(restored, (const uint8_t *)after, strlen(after), &after_kind, &after_ct, &after_ct_len) == E2EE_OK);
    uint8_t *after_pt = NULL;
    size_t after_pt_len = 0;
    CHECK(e2ee_session_decrypt(b, after_kind, after_ct, after_ct_len, &after_pt, &after_pt_len) == E2EE_OK);
    CHECK(after_pt_len == strlen(after) && memcmp(after_pt, after, after_pt_len) == 0);
    e2ee_bytes_free(after_pt, after_pt_len);
    e2ee_bytes_free(after_ct, after_ct_len);

    /* Account pickle: the restored account has the same identity key. */
    uint8_t *account_sealed = NULL;
    size_t account_sealed_len = 0;
    CHECK(e2ee_account_pickle(bob, key, &account_sealed, &account_sealed_len) == E2EE_OK);
    E2eeAccount *bob2 = NULL;
    CHECK(e2ee_account_from_pickle(account_sealed, account_sealed_len, wrong, &bob2) == E2EE_ERR_PICKLE);
    CHECK(bob2 == NULL);
    CHECK(e2ee_account_from_pickle(account_sealed, account_sealed_len, key, &bob2) == E2EE_OK);
    e2ee_bytes_free(account_sealed, account_sealed_len);
    uint8_t bob2_id[32];
    CHECK(e2ee_account_curve25519_key(bob2, bob2_id) == E2EE_OK);
    CHECK(memcmp(bob_id, bob2_id, 32) == 0);

    e2ee_session_free(restored);
    e2ee_session_free(a);
    e2ee_session_free(b);
    e2ee_account_free(bob2);
    e2ee_account_free(alice);
    e2ee_account_free(bob);

    if (failures != 0) {
        fprintf(stderr, "e2ee_olm C smoke test: %d check(s) failed\n", failures);
        return 1;
    }
    puts("e2ee_olm C smoke test: all checks passed");
    return 0;
}
