/*
 * e2ee_olm.h: C interface over vodozemac's Olm, for the end-to-end encrypted
 * one-to-one chat. See E2EE_DESIGN.md, sections 4 to 6.
 *
 * Keep this header in step with native/e2ee_olm/src/lib.rs. The script
 * native/e2ee_olm/tests/check_exports.sh fails when the two differ.
 *
 * Conventions
 * - Functions return E2EE_OK (0) or a negative E2EE_ERR_* code. The
 *   constructors return NULL on failure, and e2ee_abi_version returns the
 *   interface version.
 * - Keys are 32 raw bytes. Signatures are 64 raw bytes.
 * - Buffers handed to the caller are owned by the library. Release each with
 *   e2ee_bytes_free. Release handles with their own *_free function.
 * - A handle must not be used from two threads at once.
 * - Olm message types: 0 is a pre-key message, 1 is a normal message.
 */
#ifndef E2EE_OLM_H
#define E2EE_OLM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define E2EE_ABI_VERSION 1

#define E2EE_OK 0
#define E2EE_ERR_NULL (-1)
#define E2EE_ERR_DECODE (-2)
#define E2EE_ERR_SESSION (-3)
#define E2EE_ERR_DECRYPT (-4)
#define E2EE_ERR_ENCRYPT (-5)
#define E2EE_ERR_PICKLE (-6)
#define E2EE_ERR_ARGUMENT (-7)
#define E2EE_ERR_SIGNATURE (-8)
#define E2EE_ERR_PANIC (-100)

typedef struct E2eeAccount E2eeAccount;
typedef struct E2eeSession E2eeSession;

/* Interface version. Check it once after loading the library. */
uint32_t e2ee_abi_version(void);

/* Frees a buffer returned by this library. A NULL pointer is ignored. */
void e2ee_bytes_free(uint8_t *ptr, size_t len);

/*
 * Accounts: identity keys, one-time keys, signatures and the fallback key.
 */

/* Creates an account with fresh identity keys. Returns NULL on failure. */
E2eeAccount *e2ee_account_new(void);

/* Frees an account. A NULL pointer is ignored. */
void e2ee_account_free(E2eeAccount *account);

/* Writes the Curve25519 identity key (32 bytes) to out. */
int32_t e2ee_account_curve25519_key(const E2eeAccount *account, uint8_t *out);

/* Writes the Ed25519 signing key (32 bytes) to out. */
int32_t e2ee_account_ed25519_key(const E2eeAccount *account, uint8_t *out);

/* Creates count new one-time keys. At most 100 per call. */
int32_t e2ee_account_generate_one_time_keys(E2eeAccount *account, size_t count);

/*
 * Copies up to capacity unpublished one-time keys (32 bytes each) to out_keys,
 * in no particular order, and writes the number copied to out_count.
 */
int32_t e2ee_account_one_time_keys(const E2eeAccount *account, uint8_t *out_keys, size_t capacity, size_t *out_count);

/* Marks the unpublished one-time and fallback keys as published. */
int32_t e2ee_account_mark_keys_published(E2eeAccount *account);

/* Signs message with the Ed25519 key and writes the 64-byte signature to out_signature. */
int32_t e2ee_account_sign(const E2eeAccount *account, const uint8_t *message, size_t message_len, uint8_t *out_signature);

/*
 * Copies the unpublished fallback key (32 bytes) to out_key and sets
 * out_present to 1. When there is none, sets out_present to 0.
 */
int32_t e2ee_account_fallback_key(const E2eeAccount *account, uint8_t *out_key, size_t *out_present);

/* Generates a new fallback key. Call it once the previous key has been published. */
int32_t e2ee_account_generate_fallback_key(E2eeAccount *account);

/*
 * Encrypts the account under a 32-byte key. The output is text, returned in a
 * buffer to release with e2ee_bytes_free.
 */
int32_t e2ee_account_pickle(const E2eeAccount *account, const uint8_t *key, uint8_t **out_ptr, size_t *out_len);

/* Restores an account from e2ee_account_pickle output. A wrong key gives E2EE_ERR_PICKLE. */
int32_t e2ee_account_from_pickle(const uint8_t *data, size_t len, const uint8_t *key, E2eeAccount **out);

/*
 * Checks a signature made by e2ee_account_sign with the matching Ed25519 public
 * key. Returns E2EE_OK when valid, E2EE_ERR_SIGNATURE when not, and
 * E2EE_ERR_ARGUMENT when the public key is not a valid key.
 */
int32_t e2ee_verify_signature(const uint8_t *ed25519_key, const uint8_t *message, size_t message_len, const uint8_t *signature);

/*
 * Sessions. Only version 2 sessions (full MAC) are made or accepted.
 */

/* Starts an outbound session from the peer's identity key and one of its one-time keys. */
int32_t e2ee_session_create_outbound(const E2eeAccount *account, const uint8_t *their_identity_key, const uint8_t *their_one_time_key, E2eeSession **out);

/*
 * Creates the receiving side from the first (pre-key) message. Writes the
 * session and the plaintext of that message. The plaintext buffer is released
 * with e2ee_bytes_free.
 */
int32_t e2ee_session_create_inbound(E2eeAccount *account, const uint8_t *their_identity_key, const uint8_t *prekey_message, size_t prekey_len, E2eeSession **out_session, uint8_t **out_plaintext, size_t *out_plaintext_len);

/* Encrypts plaintext. Writes the Olm message type (0 or 1) to out_type and the ciphertext to a buffer. */
int32_t e2ee_session_encrypt(E2eeSession *session, const uint8_t *plaintext, size_t plaintext_len, size_t *out_type, uint8_t **out_ptr, size_t *out_len);

/* Decrypts a message of the given Olm type. A replayed or altered message gives E2EE_ERR_DECRYPT. */
int32_t e2ee_session_decrypt(E2eeSession *session, size_t message_type, const uint8_t *message, size_t message_len, uint8_t **out_ptr, size_t *out_len);

/* Writes the session id (UTF-8 text). Both sides of a session get the same id. */
int32_t e2ee_session_id(const E2eeSession *session, uint8_t **out_ptr, size_t *out_len);

/* Encrypts the session under a 32-byte key, for the local encrypted store. */
int32_t e2ee_session_pickle(const E2eeSession *session, const uint8_t *key, uint8_t **out_ptr, size_t *out_len);

/* Restores a session from e2ee_session_pickle output. */
int32_t e2ee_session_from_pickle(const uint8_t *data, size_t len, const uint8_t *key, E2eeSession **out);

/* Frees a session. A NULL pointer is ignored. */
void e2ee_session_free(E2eeSession *session);

#ifdef __cplusplus
}
#endif

#endif /* E2EE_OLM_H */
