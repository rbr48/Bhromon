//! C interface over vodozemac's Olm implementation, for the end-to-end
//! encrypted one-to-one chat (ROADMAP Track E, milestone M1).
//!
//! Conventions
//! - Every function returns `E2EE_OK` (0) or a negative `E2EE_ERR_*` code.
//! - Keys are 32 raw bytes. Pickle keys are 32 bytes.
//! - Buffers returned to the caller are owned by this library and are released
//!   with `e2ee_bytes_free`. Handles are released with their own `*_free`.
//! - A panic is caught at the boundary and reported as `E2EE_ERR_PANIC`.
//! - Message types follow Olm: 0 is a pre-key message, 1 is a normal message.
//! - A handle must not be used from two threads at once.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use vodozemac::olm::{Account, AccountPickle, OlmMessage, Session, SessionConfig, SessionPickle};
use vodozemac::{Curve25519PublicKey, Ed25519PublicKey, Ed25519Signature};

/// Interface version. Bump it when a signature or a code changes.
pub const E2EE_ABI_VERSION: u32 = 1;

pub const E2EE_OK: i32 = 0;
pub const E2EE_ERR_NULL: i32 = -1;
pub const E2EE_ERR_DECODE: i32 = -2;
pub const E2EE_ERR_SESSION: i32 = -3;
pub const E2EE_ERR_DECRYPT: i32 = -4;
pub const E2EE_ERR_ENCRYPT: i32 = -5;
pub const E2EE_ERR_PICKLE: i32 = -6;
pub const E2EE_ERR_ARGUMENT: i32 = -7;
pub const E2EE_ERR_SIGNATURE: i32 = -8;
pub const E2EE_ERR_PANIC: i32 = -100;

/// Most one-time keys one call may create.
const MAX_ONE_TIME_KEYS_PER_CALL: usize = 100;

/// A local Olm account: identity keys, one-time keys and session creation.
pub struct E2eeAccount {
    inner: Account,
}

/// One Olm session with one peer device.
pub struct E2eeSession {
    inner: Session,
}

/// Runs `body`, turning a panic into `E2EE_ERR_PANIC`.
fn guard(body: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(E2EE_ERR_PANIC)
}

/// Borrows `len` bytes at `ptr`. A null pointer is accepted only with `len == 0`.
///
/// # Safety
/// If `len > 0`, `ptr` must be valid for reads of `len` bytes.
unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a [u8]> {
    if len == 0 {
        return Some(&[]);
    }
    if ptr.is_null() {
        return None;
    }
    Some(slice::from_raw_parts(ptr, len))
}

/// Borrows a 32-byte key at `ptr`.
///
/// # Safety
/// `ptr`, if not null, must be valid for reads of 32 bytes.
unsafe fn key32<'a>(ptr: *const u8) -> Option<&'a [u8; 32]> {
    if ptr.is_null() {
        None
    } else {
        Some(&*(ptr as *const [u8; 32]))
    }
}

/// Hands `data` to the caller as a buffer released with `e2ee_bytes_free`.
///
/// # Safety
/// `out_ptr` and `out_len` must be valid for writes.
unsafe fn give_bytes(data: Vec<u8>, out_ptr: *mut *mut u8, out_len: *mut usize) {
    let boxed = data.into_boxed_slice();
    *out_len = boxed.len();
    *out_ptr = Box::into_raw(boxed) as *mut u8;
}

/// The interface version. Callers check it once after loading the library.
#[no_mangle]
pub extern "C" fn e2ee_abi_version() -> u32 {
    E2EE_ABI_VERSION
}

/// Frees a buffer returned by this library. A null pointer is ignored.
///
/// # Safety
/// `ptr` and `len` must be exactly the values the library returned, and the
/// buffer must not have been freed already.
#[no_mangle]
pub unsafe extern "C" fn e2ee_bytes_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() {
        return;
    }
    drop(Box::from_raw(ptr::slice_from_raw_parts_mut(ptr, len)));
}

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------

/// Creates a new account with fresh identity keys. Returns null on failure.
#[no_mangle]
pub extern "C" fn e2ee_account_new() -> *mut E2eeAccount {
    catch_unwind(AssertUnwindSafe(|| {
        Box::into_raw(Box::new(E2eeAccount {
            inner: Account::new(),
        }))
    }))
    .unwrap_or(ptr::null_mut())
}

/// Frees an account. A null pointer is ignored.
///
/// # Safety
/// `account` must come from this library and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_free(account: *mut E2eeAccount) {
    if !account.is_null() {
        drop(Box::from_raw(account));
    }
}

/// Writes the account's Curve25519 identity key (32 bytes) to `out`.
///
/// # Safety
/// `account` must be a live handle and `out` must be valid for 32 writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_curve25519_key(
    account: *const E2eeAccount,
    out: *mut u8,
) -> i32 {
    guard(|| {
        if account.is_null() || out.is_null() {
            return E2EE_ERR_NULL;
        }
        let key = (*account).inner.curve25519_key();
        ptr::copy_nonoverlapping(key.as_bytes().as_ptr(), out, 32);
        E2EE_OK
    })
}

/// Writes the account's Ed25519 signing key (32 bytes) to `out`.
///
/// # Safety
/// `account` must be a live handle and `out` must be valid for 32 writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_ed25519_key(
    account: *const E2eeAccount,
    out: *mut u8,
) -> i32 {
    guard(|| {
        if account.is_null() || out.is_null() {
            return E2EE_ERR_NULL;
        }
        let key = (*account).inner.ed25519_key();
        ptr::copy_nonoverlapping(key.as_bytes().as_ptr(), out, 32);
        E2EE_OK
    })
}

/// Creates `count` new one-time keys. At most 100 per call.
///
/// # Safety
/// `account` must be a live handle.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_generate_one_time_keys(
    account: *mut E2eeAccount,
    count: usize,
) -> i32 {
    guard(|| {
        if account.is_null() {
            return E2EE_ERR_NULL;
        }
        if count == 0 || count > MAX_ONE_TIME_KEYS_PER_CALL {
            return E2EE_ERR_ARGUMENT;
        }
        (*account).inner.generate_one_time_keys(count);
        E2EE_OK
    })
}

/// Copies up to `capacity` unpublished one-time keys, 32 bytes each, into
/// `out_keys`. Writes the number copied to `out_count`.
///
/// # Safety
/// `out_keys` must be valid for `capacity * 32` writes and `out_count` for one.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_one_time_keys(
    account: *const E2eeAccount,
    out_keys: *mut u8,
    capacity: usize,
    out_count: *mut usize,
) -> i32 {
    guard(|| {
        if account.is_null() || out_count.is_null() || (out_keys.is_null() && capacity > 0) {
            return E2EE_ERR_NULL;
        }
        let keys = (*account).inner.one_time_keys();
        let n = keys.len().min(capacity);
        for (i, key) in keys.values().take(n).enumerate() {
            ptr::copy_nonoverlapping(key.as_bytes().as_ptr(), out_keys.add(i * 32), 32);
        }
        *out_count = n;
        E2EE_OK
    })
}

/// Marks the current one-time keys as published. Call after they are uploaded.
///
/// # Safety
/// `account` must be a live handle.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_mark_keys_published(account: *mut E2eeAccount) -> i32 {
    guard(|| {
        if account.is_null() {
            return E2EE_ERR_NULL;
        }
        (*account).inner.mark_keys_as_published();
        E2EE_OK
    })
}

/// Signs `message` with the account's Ed25519 key and writes the 64-byte
/// signature to `out_signature`. The app signs each one-time key this way, so a
/// peer can tell that a key came from this device and not from the server.
///
/// # Safety
/// `account` must be a live handle, `message` valid for `message_len` reads, and
/// `out_signature` valid for 64 writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_sign(
    account: *const E2eeAccount,
    message: *const u8,
    message_len: usize,
    out_signature: *mut u8,
) -> i32 {
    guard(|| {
        if account.is_null() || out_signature.is_null() {
            return E2EE_ERR_NULL;
        }
        let Some(message) = bytes(message, message_len) else {
            return E2EE_ERR_NULL;
        };
        let signature = (*account).inner.sign(message).to_bytes();
        ptr::copy_nonoverlapping(signature.as_ptr(), out_signature, 64);
        E2EE_OK
    })
}

/// Checks a signature made by `e2ee_account_sign` against an Ed25519 public key.
/// Returns `E2EE_OK` when the signature is valid, `E2EE_ERR_SIGNATURE` when it is
/// not, and `E2EE_ERR_ARGUMENT` when the public key is not a valid key.
///
/// # Safety
/// `ed25519_key` must be valid for 32 reads, `message` for `message_len` reads,
/// and `signature` for 64 reads.
#[no_mangle]
pub unsafe extern "C" fn e2ee_verify_signature(
    ed25519_key: *const u8,
    message: *const u8,
    message_len: usize,
    signature: *const u8,
) -> i32 {
    guard(|| {
        let (Some(key), Some(message), Some(signature)) = (
            key32(ed25519_key),
            bytes(message, message_len),
            bytes(signature, 64),
        ) else {
            return E2EE_ERR_NULL;
        };
        let Ok(key) = Ed25519PublicKey::from_slice(key) else {
            return E2EE_ERR_ARGUMENT;
        };
        let Ok(signature) = Ed25519Signature::from_slice(signature) else {
            return E2EE_ERR_SIGNATURE;
        };
        match key.verify(message, &signature) {
            Ok(()) => E2EE_OK,
            Err(_) => E2EE_ERR_SIGNATURE,
        }
    })
}

/// Writes the unpublished fallback key (32 bytes) to `out_key` and sets
/// `out_present` to 1. When there is no unpublished fallback key, sets
/// `out_present` to 0 and writes nothing. Peers use the fallback key only after
/// the one-time keys are used up.
///
/// # Safety
/// `account` must be a live handle, `out_key` valid for 32 writes, and
/// `out_present` valid for one write.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_fallback_key(
    account: *const E2eeAccount,
    out_key: *mut u8,
    out_present: *mut usize,
) -> i32 {
    guard(|| {
        if account.is_null() || out_key.is_null() || out_present.is_null() {
            return E2EE_ERR_NULL;
        }
        let keys = (*account).inner.fallback_key();
        match keys.values().next() {
            Some(key) => {
                ptr::copy_nonoverlapping(key.as_bytes().as_ptr(), out_key, 32);
                *out_present = 1;
            }
            None => *out_present = 0,
        }
        E2EE_OK
    })
}

/// Generates a new fallback key. Call it once the previous key has been
/// published. The account keeps the previous fallback key too, so pre-key
/// messages that use it still decrypt; an older one is dropped.
///
/// # Safety
/// `account` must be a live handle.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_generate_fallback_key(account: *mut E2eeAccount) -> i32 {
    guard(|| {
        if account.is_null() {
            return E2EE_ERR_NULL;
        }
        (*account).inner.generate_fallback_key();
        E2EE_OK
    })
}

/// Encrypts the account under a 32-byte key. The output is a text string that
/// the app stores in the local encrypted store.
///
/// # Safety
/// `key` must be valid for 32 reads, and `out_ptr` and `out_len` for writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_pickle(
    account: *const E2eeAccount,
    key: *const u8,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        if account.is_null() || out_ptr.is_null() || out_len.is_null() {
            return E2EE_ERR_NULL;
        }
        let Some(key) = key32(key) else {
            return E2EE_ERR_NULL;
        };
        let sealed = (*account).inner.pickle().encrypt(key);
        give_bytes(sealed.into_bytes(), out_ptr, out_len);
        E2EE_OK
    })
}

/// Restores an account from a pickle made by `e2ee_account_pickle`. A wrong key
/// or damaged data gives `E2EE_ERR_PICKLE`.
///
/// # Safety
/// `data` must be valid for `len` reads, `key` for 32 reads, and `out` for one write.
#[no_mangle]
pub unsafe extern "C" fn e2ee_account_from_pickle(
    data: *const u8,
    len: usize,
    key: *const u8,
    out: *mut *mut E2eeAccount,
) -> i32 {
    guard(|| {
        if out.is_null() {
            return E2EE_ERR_NULL;
        }
        let (Some(data), Some(key)) = (bytes(data, len), key32(key)) else {
            return E2EE_ERR_NULL;
        };
        let Ok(text) = std::str::from_utf8(data) else {
            return E2EE_ERR_PICKLE;
        };
        let Ok(pickle) = AccountPickle::from_encrypted(text, key) else {
            return E2EE_ERR_PICKLE;
        };
        *out = Box::into_raw(Box::new(E2eeAccount {
            inner: Account::from_pickle(pickle),
        }));
        E2EE_OK
    })
}

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/// Starts an outbound session from the peer's identity key and one of its
/// one-time keys. Uses session version 1: the MAC is truncated to 8 bytes, as
/// libolm does (E2EE_DESIGN.md, decision D10).
///
/// # Safety
/// `their_identity_key` and `their_one_time_key` must each be valid for 32
/// reads, and `out` for one write.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_create_outbound(
    account: *const E2eeAccount,
    their_identity_key: *const u8,
    their_one_time_key: *const u8,
    out: *mut *mut E2eeSession,
) -> i32 {
    guard(|| {
        if account.is_null() || out.is_null() {
            return E2EE_ERR_NULL;
        }
        let (Some(identity), Some(one_time)) =
            (key32(their_identity_key), key32(their_one_time_key))
        else {
            return E2EE_ERR_NULL;
        };
        let session = match (*account).inner.create_outbound_session(
            SessionConfig::version_1(),
            Curve25519PublicKey::from_bytes(*identity),
            Curve25519PublicKey::from_bytes(*one_time),
        ) {
            Ok(session) => session,
            Err(_) => return E2EE_ERR_SESSION,
        };
        *out = Box::into_raw(Box::new(E2eeSession { inner: session }));
        E2EE_OK
    })
}

/// Creates the receiving side of a session from the first (pre-key) message.
/// Returns the session and the plaintext of that message.
///
/// # Safety
/// `their_identity_key` must be valid for 32 reads, `prekey_message` for
/// `prekey_len` reads, and the three out-parameters for writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_create_inbound(
    account: *mut E2eeAccount,
    their_identity_key: *const u8,
    prekey_message: *const u8,
    prekey_len: usize,
    out_session: *mut *mut E2eeSession,
    out_plaintext: *mut *mut u8,
    out_plaintext_len: *mut usize,
) -> i32 {
    guard(|| {
        if account.is_null()
            || out_session.is_null()
            || out_plaintext.is_null()
            || out_plaintext_len.is_null()
        {
            return E2EE_ERR_NULL;
        }
        let (Some(identity), Some(body)) =
            (key32(their_identity_key), bytes(prekey_message, prekey_len))
        else {
            return E2EE_ERR_NULL;
        };
        let message = match OlmMessage::from_parts(0, body) {
            Ok(OlmMessage::PreKey(message)) => message,
            _ => return E2EE_ERR_DECODE,
        };
        let result = match (*account).inner.create_inbound_session(
            SessionConfig::version_1(),
            Curve25519PublicKey::from_bytes(*identity),
            &message,
        ) {
            Ok(result) => result,
            Err(_) => return E2EE_ERR_SESSION,
        };
        give_bytes(result.plaintext, out_plaintext, out_plaintext_len);
        *out_session = Box::into_raw(Box::new(E2eeSession {
            inner: result.session,
        }));
        E2EE_OK
    })
}

/// Encrypts `plaintext`. Writes the Olm message type (0 or 1) to `out_type` and
/// the ciphertext to a new buffer.
///
/// # Safety
/// `session` must be a live handle. `plaintext` must be valid for `len` reads,
/// and the out-parameters for writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_encrypt(
    session: *mut E2eeSession,
    plaintext: *const u8,
    plaintext_len: usize,
    out_type: *mut usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        if session.is_null() || out_type.is_null() || out_ptr.is_null() || out_len.is_null() {
            return E2EE_ERR_NULL;
        }
        let Some(plain) = bytes(plaintext, plaintext_len) else {
            return E2EE_ERR_NULL;
        };
        let message = match (*session).inner.encrypt(plain) {
            Ok(message) => message,
            Err(_) => return E2EE_ERR_ENCRYPT,
        };
        let (kind, body) = message.to_parts();
        *out_type = kind;
        give_bytes(body, out_ptr, out_len);
        E2EE_OK
    })
}

/// Decrypts a message of the given Olm type (0 or 1). A replayed or foreign
/// message gives `E2EE_ERR_DECRYPT`.
///
/// # Safety
/// `session` must be a live handle. `message` must be valid for `len` reads,
/// and the out-parameters for writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_decrypt(
    session: *mut E2eeSession,
    message_type: usize,
    message: *const u8,
    message_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        if session.is_null() || out_ptr.is_null() || out_len.is_null() {
            return E2EE_ERR_NULL;
        }
        let Some(body) = bytes(message, message_len) else {
            return E2EE_ERR_NULL;
        };
        let parsed = match OlmMessage::from_parts(message_type, body) {
            Ok(parsed) => parsed,
            Err(_) => return E2EE_ERR_DECODE,
        };
        let plaintext = match (*session).inner.decrypt(&parsed) {
            Ok(plaintext) => plaintext,
            Err(_) => return E2EE_ERR_DECRYPT,
        };
        give_bytes(plaintext, out_ptr, out_len);
        E2EE_OK
    })
}

/// Writes the session id (UTF-8 text) to a new buffer. Both sides of a session
/// get the same id.
///
/// # Safety
/// `session` must be a live handle, and the out-parameters must be valid for writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_id(
    session: *const E2eeSession,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        if session.is_null() || out_ptr.is_null() || out_len.is_null() {
            return E2EE_ERR_NULL;
        }
        give_bytes((*session).inner.session_id().into_bytes(), out_ptr, out_len);
        E2EE_OK
    })
}

/// Encrypts the session under a 32-byte key, for storage in the local encrypted store.
///
/// # Safety
/// `session` must be a live handle, `key` valid for 32 reads, and the out-parameters for writes.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_pickle(
    session: *const E2eeSession,
    key: *const u8,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guard(|| {
        if session.is_null() || out_ptr.is_null() || out_len.is_null() {
            return E2EE_ERR_NULL;
        }
        let Some(key) = key32(key) else {
            return E2EE_ERR_NULL;
        };
        let sealed = (*session).inner.pickle().encrypt(key);
        give_bytes(sealed.into_bytes(), out_ptr, out_len);
        E2EE_OK
    })
}

/// Restores a session from a pickle made by `e2ee_session_pickle`.
///
/// # Safety
/// `data` must be valid for `len` reads, `key` for 32 reads, and `out` for one write.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_from_pickle(
    data: *const u8,
    len: usize,
    key: *const u8,
    out: *mut *mut E2eeSession,
) -> i32 {
    guard(|| {
        if out.is_null() {
            return E2EE_ERR_NULL;
        }
        let (Some(data), Some(key)) = (bytes(data, len), key32(key)) else {
            return E2EE_ERR_NULL;
        };
        let Ok(text) = std::str::from_utf8(data) else {
            return E2EE_ERR_PICKLE;
        };
        let Ok(pickle) = SessionPickle::from_encrypted(text, key) else {
            return E2EE_ERR_PICKLE;
        };
        *out = Box::into_raw(Box::new(E2eeSession {
            inner: Session::from_pickle(pickle),
        }));
        E2EE_OK
    })
}

/// Frees a session. A null pointer is ignored.
///
/// # Safety
/// `session` must come from this library and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn e2ee_session_free(session: *mut E2eeSession) {
    if !session.is_null() {
        drop(Box::from_raw(session));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Copies a library-owned buffer into a `Vec` and frees the buffer.
    unsafe fn take(ptr: *mut u8, len: usize) -> Vec<u8> {
        let copy = slice::from_raw_parts(ptr, len).to_vec();
        e2ee_bytes_free(ptr, len);
        copy
    }

    /// Encrypts `plain` on `session`, returning the Olm type and the body.
    unsafe fn encrypt(session: *mut E2eeSession, plain: &[u8]) -> (usize, Vec<u8>) {
        let mut kind = usize::MAX;
        let mut ptr_out = ptr::null_mut();
        let mut len_out = 0usize;
        assert_eq!(
            e2ee_session_encrypt(
                session,
                plain.as_ptr(),
                plain.len(),
                &mut kind,
                &mut ptr_out,
                &mut len_out
            ),
            E2EE_OK
        );
        (kind, take(ptr_out, len_out))
    }

    /// Decrypts `body` of Olm type `kind` on `session`.
    unsafe fn decrypt(session: *mut E2eeSession, kind: usize, body: &[u8]) -> i32 {
        let mut ptr_out = ptr::null_mut();
        let mut len_out = 0usize;
        let code = e2ee_session_decrypt(
            session,
            kind,
            body.as_ptr(),
            body.len(),
            &mut ptr_out,
            &mut len_out,
        );
        if code == E2EE_OK {
            e2ee_bytes_free(ptr_out, len_out);
        }
        code
    }

    #[test]
    fn abi_version_is_one() {
        assert_eq!(e2ee_abi_version(), 1);
    }

    #[test]
    fn two_accounts_exchange_messages_through_the_c_interface() {
        unsafe {
            let alice = e2ee_account_new();
            let bob = e2ee_account_new();
            assert!(!alice.is_null() && !bob.is_null());

            assert_eq!(e2ee_account_generate_one_time_keys(bob, 5), E2EE_OK);
            let mut bob_one_time = [0u8; 32];
            let mut published = 0usize;
            assert_eq!(
                e2ee_account_one_time_keys(bob, bob_one_time.as_mut_ptr(), 1, &mut published),
                E2EE_OK
            );
            assert_eq!(published, 1);

            let mut bob_identity = [0u8; 32];
            let mut alice_identity = [0u8; 32];
            assert_eq!(
                e2ee_account_curve25519_key(bob, bob_identity.as_mut_ptr()),
                E2EE_OK
            );
            assert_eq!(
                e2ee_account_curve25519_key(alice, alice_identity.as_mut_ptr()),
                E2EE_OK
            );

            let mut a_session = ptr::null_mut();
            assert_eq!(
                e2ee_session_create_outbound(
                    alice,
                    bob_identity.as_ptr(),
                    bob_one_time.as_ptr(),
                    &mut a_session
                ),
                E2EE_OK
            );

            // The first message is a pre-key message (type 0).
            let (kind, prekey) = encrypt(a_session, b"hello bob");
            assert_eq!(kind, 0);

            let mut b_session = ptr::null_mut();
            let mut plain_ptr = ptr::null_mut();
            let mut plain_len = 0usize;
            assert_eq!(
                e2ee_session_create_inbound(
                    bob,
                    alice_identity.as_ptr(),
                    prekey.as_ptr(),
                    prekey.len(),
                    &mut b_session,
                    &mut plain_ptr,
                    &mut plain_len,
                ),
                E2EE_OK
            );
            assert_eq!(take(plain_ptr, plain_len), b"hello bob");

            // Replaying the pre-key message must not decrypt again.
            assert_ne!(decrypt(b_session, 0, &prekey), E2EE_OK);

            // Both directions, several times, so the ratchet turns over.
            for i in 0..5 {
                let (kind, body) = encrypt(b_session, format!("reply {i}").as_bytes());
                assert_eq!(kind, 1);
                assert_eq!(decrypt(a_session, kind, &body), E2EE_OK);

                let (kind, body) = encrypt(a_session, format!("ping {i}").as_bytes());
                assert_eq!(decrypt(b_session, kind, &body), E2EE_OK);
            }

            // Both sides agree on the session id.
            let mut id_a = ptr::null_mut();
            let mut id_a_len = 0usize;
            let mut id_b = ptr::null_mut();
            let mut id_b_len = 0usize;
            assert_eq!(
                e2ee_session_id(a_session, &mut id_a, &mut id_a_len),
                E2EE_OK
            );
            assert_eq!(
                e2ee_session_id(b_session, &mut id_b, &mut id_b_len),
                E2EE_OK
            );
            assert_eq!(take(id_a, id_a_len), take(id_b, id_b_len));

            e2ee_session_free(a_session);
            e2ee_session_free(b_session);
            e2ee_account_free(alice);
            e2ee_account_free(bob);
        }
    }

    #[test]
    fn pickles_round_trip_and_refuse_a_wrong_key() {
        unsafe {
            let account = e2ee_account_new();
            let key = [7u8; 32];
            let mut sealed = ptr::null_mut();
            let mut sealed_len = 0usize;
            assert_eq!(
                e2ee_account_pickle(account, key.as_ptr(), &mut sealed, &mut sealed_len),
                E2EE_OK
            );
            let text = take(sealed, sealed_len);

            let mut restored = ptr::null_mut();
            assert_eq!(
                e2ee_account_from_pickle(text.as_ptr(), text.len(), key.as_ptr(), &mut restored),
                E2EE_OK
            );
            let mut before = [0u8; 32];
            let mut after = [0u8; 32];
            assert_eq!(
                e2ee_account_curve25519_key(account, before.as_mut_ptr()),
                E2EE_OK
            );
            assert_eq!(
                e2ee_account_curve25519_key(restored, after.as_mut_ptr()),
                E2EE_OK
            );
            assert_eq!(before, after);

            let wrong = [9u8; 32];
            let mut refused = ptr::null_mut();
            assert_eq!(
                e2ee_account_from_pickle(text.as_ptr(), text.len(), wrong.as_ptr(), &mut refused),
                E2EE_ERR_PICKLE
            );
            assert!(refused.is_null());

            e2ee_account_free(restored);
            e2ee_account_free(account);
        }
    }

    #[test]
    fn null_pointers_and_bad_arguments_are_refused_not_crashed() {
        unsafe {
            assert_eq!(
                e2ee_account_curve25519_key(ptr::null(), ptr::null_mut()),
                E2EE_ERR_NULL
            );
            let account = e2ee_account_new();
            assert_eq!(
                e2ee_account_generate_one_time_keys(account, 0),
                E2EE_ERR_ARGUMENT
            );
            assert_eq!(
                e2ee_account_generate_one_time_keys(account, MAX_ONE_TIME_KEYS_PER_CALL + 1),
                E2EE_ERR_ARGUMENT
            );
            // A message of an unknown Olm type is a decode error, not a panic.
            let mut session = ptr::null_mut();
            let zero = [0u8; 32];
            assert_eq!(
                e2ee_session_create_outbound(account, zero.as_ptr(), zero.as_ptr(), &mut session),
                E2EE_ERR_SESSION
            );
            e2ee_account_free(account);
            e2ee_bytes_free(ptr::null_mut(), 0);
            e2ee_session_free(ptr::null_mut());
        }
    }

    #[test]
    fn signatures_verify_only_for_the_signed_message_and_key() {
        unsafe {
            let account = e2ee_account_new();
            let other = e2ee_account_new();
            let message = b"one-time key";
            let mut signature = [0u8; 64];
            assert_eq!(
                e2ee_account_sign(
                    account,
                    message.as_ptr(),
                    message.len(),
                    signature.as_mut_ptr()
                ),
                E2EE_OK
            );
            let mut key = [0u8; 32];
            let mut other_key = [0u8; 32];
            assert_eq!(e2ee_account_ed25519_key(account, key.as_mut_ptr()), E2EE_OK);
            assert_eq!(
                e2ee_account_ed25519_key(other, other_key.as_mut_ptr()),
                E2EE_OK
            );

            let check = |key: &[u8; 32], msg: &[u8]| {
                e2ee_verify_signature(key.as_ptr(), msg.as_ptr(), msg.len(), signature.as_ptr())
            };
            assert_eq!(check(&key, message), E2EE_OK);
            assert_eq!(check(&key, b"another message"), E2EE_ERR_SIGNATURE);
            assert_eq!(check(&other_key, message), E2EE_ERR_SIGNATURE);

            e2ee_account_free(other);
            e2ee_account_free(account);
        }
    }

    #[test]
    fn fallback_key_is_reported_until_it_is_marked_published() {
        unsafe {
            let account = e2ee_account_new();
            let mut key = [0u8; 32];
            let mut present = usize::MAX;
            assert_eq!(
                e2ee_account_fallback_key(account, key.as_mut_ptr(), &mut present),
                E2EE_OK
            );
            assert_eq!(present, 0);

            assert_eq!(e2ee_account_generate_fallback_key(account), E2EE_OK);
            assert_eq!(
                e2ee_account_fallback_key(account, key.as_mut_ptr(), &mut present),
                E2EE_OK
            );
            assert_eq!(present, 1);
            assert_ne!(key, [0u8; 32]);

            assert_eq!(e2ee_account_mark_keys_published(account), E2EE_OK);
            assert_eq!(
                e2ee_account_fallback_key(account, key.as_mut_ptr(), &mut present),
                E2EE_OK
            );
            assert_eq!(present, 0);

            e2ee_account_free(account);
        }
    }

    #[test]
    fn a_tampered_message_is_refused_and_the_real_one_still_decrypts() {
        unsafe {
            let alice = e2ee_account_new();
            let bob = e2ee_account_new();
            assert_eq!(e2ee_account_generate_one_time_keys(bob, 1), E2EE_OK);
            let mut bob_one_time = [0u8; 32];
            let mut published = 0usize;
            assert_eq!(
                e2ee_account_one_time_keys(bob, bob_one_time.as_mut_ptr(), 1, &mut published),
                E2EE_OK
            );
            let mut bob_identity = [0u8; 32];
            let mut alice_identity = [0u8; 32];
            assert_eq!(
                e2ee_account_curve25519_key(bob, bob_identity.as_mut_ptr()),
                E2EE_OK
            );
            assert_eq!(
                e2ee_account_curve25519_key(alice, alice_identity.as_mut_ptr()),
                E2EE_OK
            );

            let mut a_session = ptr::null_mut();
            assert_eq!(
                e2ee_session_create_outbound(
                    alice,
                    bob_identity.as_ptr(),
                    bob_one_time.as_ptr(),
                    &mut a_session
                ),
                E2EE_OK
            );
            let (_, prekey) = encrypt(a_session, b"first");
            let mut b_session = ptr::null_mut();
            let mut plain_ptr = ptr::null_mut();
            let mut plain_len = 0usize;
            assert_eq!(
                e2ee_session_create_inbound(
                    bob,
                    alice_identity.as_ptr(),
                    prekey.as_ptr(),
                    prekey.len(),
                    &mut b_session,
                    &mut plain_ptr,
                    &mut plain_len,
                ),
                E2EE_OK
            );
            assert_eq!(take(plain_ptr, plain_len), b"first");

            // Bob replies, so Alice's side of the ratchet is established too.
            let (kind, reply) = encrypt(b_session, b"reply");
            assert_eq!(kind, 1);
            assert_eq!(decrypt(a_session, kind, &reply), E2EE_OK);

            // Changing the last byte, which is inside the MAC, must fail. The
            // failure must not disturb the session: the genuine message still
            // decrypts afterwards.
            let (kind, genuine) = encrypt(a_session, b"second");
            let mut tampered = genuine.clone();
            let last = tampered.len() - 1;
            tampered[last] ^= 0x01;
            assert_eq!(decrypt(b_session, kind, &tampered), E2EE_ERR_DECRYPT);
            assert_eq!(decrypt(b_session, kind, &genuine), E2EE_OK);

            e2ee_session_free(a_session);
            e2ee_session_free(b_session);
            e2ee_account_free(bob);
            e2ee_account_free(alice);
        }
    }

    #[test]
    fn a_pre_key_message_is_refused_under_another_identity_key() {
        unsafe {
            let alice = e2ee_account_new();
            let bob = e2ee_account_new();
            let carol = e2ee_account_new();
            assert_eq!(e2ee_account_generate_one_time_keys(bob, 1), E2EE_OK);
            let mut bob_one_time = [0u8; 32];
            let mut published = 0usize;
            assert_eq!(
                e2ee_account_one_time_keys(bob, bob_one_time.as_mut_ptr(), 1, &mut published),
                E2EE_OK
            );
            let mut bob_identity = [0u8; 32];
            let mut alice_identity = [0u8; 32];
            let mut carol_identity = [0u8; 32];
            assert_eq!(
                e2ee_account_curve25519_key(bob, bob_identity.as_mut_ptr()),
                E2EE_OK
            );
            assert_eq!(
                e2ee_account_curve25519_key(alice, alice_identity.as_mut_ptr()),
                E2EE_OK
            );
            assert_eq!(
                e2ee_account_curve25519_key(carol, carol_identity.as_mut_ptr()),
                E2EE_OK
            );

            let mut a_session = ptr::null_mut();
            assert_eq!(
                e2ee_session_create_outbound(
                    alice,
                    bob_identity.as_ptr(),
                    bob_one_time.as_ptr(),
                    &mut a_session
                ),
                E2EE_OK
            );
            let (kind, prekey) = encrypt(a_session, b"hello");
            assert_eq!(kind, 0);

            // Bob must not accept the message under Carol's identity key. vodozemac
            // checks the identity before it uses the one-time key, so the real
            // attempt below still succeeds.
            let mut refused = ptr::null_mut();
            let mut plain_ptr = ptr::null_mut();
            let mut plain_len = 0usize;
            assert_eq!(
                e2ee_session_create_inbound(
                    bob,
                    carol_identity.as_ptr(),
                    prekey.as_ptr(),
                    prekey.len(),
                    &mut refused,
                    &mut plain_ptr,
                    &mut plain_len,
                ),
                E2EE_ERR_SESSION
            );
            assert!(refused.is_null());

            let mut b_session = ptr::null_mut();
            assert_eq!(
                e2ee_session_create_inbound(
                    bob,
                    alice_identity.as_ptr(),
                    prekey.as_ptr(),
                    prekey.len(),
                    &mut b_session,
                    &mut plain_ptr,
                    &mut plain_len,
                ),
                E2EE_OK
            );
            assert_eq!(take(plain_ptr, plain_len), b"hello");

            e2ee_session_free(a_session);
            e2ee_session_free(b_session);
            e2ee_account_free(carol);
            e2ee_account_free(bob);
            e2ee_account_free(alice);
        }
    }

    #[test]
    fn a_version_two_session_is_refused_so_one_format_is_accepted() {
        unsafe {
            let alice = e2ee_account_new();
            let bob = e2ee_account_new();
            assert_eq!(e2ee_account_generate_one_time_keys(bob, 1), E2EE_OK);
            let mut bob_one_time = [0u8; 32];
            let mut published = 0usize;
            assert_eq!(
                e2ee_account_one_time_keys(bob, bob_one_time.as_mut_ptr(), 1, &mut published),
                E2EE_OK
            );
            let mut bob_identity = [0u8; 32];
            let mut alice_identity = [0u8; 32];
            assert_eq!(
                e2ee_account_curve25519_key(bob, bob_identity.as_mut_ptr()),
                E2EE_OK
            );
            assert_eq!(
                e2ee_account_curve25519_key(alice, alice_identity.as_mut_ptr()),
                E2EE_OK
            );

            // The C interface only makes version 1 sessions. This one is made with
            // vodozemac directly, as a peer that uses version 2 (full MAC) would make it.
            // The dev-dependencies enable the feature that version 2 needs.
            let mut v2 = (*alice)
                .inner
                .create_outbound_session(
                    SessionConfig::version_2(),
                    Curve25519PublicKey::from_bytes(bob_identity),
                    Curve25519PublicKey::from_bytes(bob_one_time),
                )
                .expect("version 2 session");
            let message = v2.encrypt(b"other format").expect("encrypt");
            let (kind, body) = message.to_parts();
            assert_eq!(kind, 0);

            let mut refused = ptr::null_mut();
            let mut plain_ptr = ptr::null_mut();
            let mut plain_len = 0usize;
            assert_eq!(
                e2ee_session_create_inbound(
                    bob,
                    alice_identity.as_ptr(),
                    body.as_ptr(),
                    body.len(),
                    &mut refused,
                    &mut plain_ptr,
                    &mut plain_len,
                ),
                E2EE_ERR_SESSION
            );
            assert!(refused.is_null());

            e2ee_account_free(bob);
            e2ee_account_free(alice);
        }
    }
}
