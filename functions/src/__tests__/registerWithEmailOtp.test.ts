import * as functions from 'firebase-functions/v1';
import {
  executeRegisterWithEmailOtp,
  RegisterWithEmailOtpDeps,
} from '../registerWithEmailOtp';
import { validateSignUpInput } from '../lib/otpStore';

function userNotFoundError(): Error & { code: string } {
  const err = new Error('User not found') as Error & { code: string };
  err.code = 'auth/user-not-found';
  return err;
}

describe('validateSignUpInput', () => {
  it('normalizes email and trims displayName', () => {
    const parsed = validateSignUpInput({
      email: '  Explorer@Bhromon.Fun ',
      otp: ' 123456 ',
      password: 'password123',
      displayName: '  Rana  ',
    });
    expect(parsed).toEqual({
      email: 'explorer@bhromon.fun',
      otp: '123456',
      password: 'password123',
      displayName: 'Rana',
    });
  });

  it('rejects non-6-digit OTP and short passwords', () => {
    expect(() =>
      validateSignUpInput({
        email: 'a@b.com',
        otp: '12345',
        password: 'password123',
      }),
    ).toThrow(functions.https.HttpsError);

    expect(() =>
      validateSignUpInput({
        email: 'a@b.com',
        otp: '123456',
        password: '12345',
      }),
    ).toThrow(functions.https.HttpsError);
  });
});

describe('executeRegisterWithEmailOtp', () => {
  it('consumes OTP and creates an emailVerified user when email is new', async () => {
    const calls: string[] = [];
    const deps: RegisterWithEmailOtpDeps = {
      consumeOtp: async (email, code) => {
        calls.push(`consume:${email}:${code}`);
      },
      getUserByEmail: async () => {
        throw userNotFoundError();
      },
      createUser: async (props) => {
        calls.push(`create:${props.email}:${props.emailVerified}:${props.displayName ?? ''}`);
        return { uid: 'uid-new-1' };
      },
    };

    const result = await executeRegisterWithEmailOtp(deps, {
      email: 'NewUser@Bhromon.fun',
      otp: '482910',
      password: 'strongPassword9',
      displayName: 'Rana',
    });

    expect(result).toEqual({ success: true, uid: 'uid-new-1' });
    expect(calls).toEqual([
      'consume:newuser@bhromon.fun:482910',
      'create:newuser@bhromon.fun:true:Rana',
    ]);
  });

  it('rejects already-existing email after OTP verification without calling createUser', async () => {
    const createUser = jest.fn();
    const deps: RegisterWithEmailOtpDeps = {
      consumeOtp: async () => {},
      getUserByEmail: async () => ({ uid: 'existing-uid' }),
      createUser,
    };

    await expect(
      executeRegisterWithEmailOtp(deps, {
        email: 'existing@bhromon.fun',
        otp: '482910',
        password: 'strongPassword9',
      }),
    ).rejects.toMatchObject({ code: 'already-exists' });
    expect(createUser).not.toHaveBeenCalled();
  });

  it('aborts cleanly if OTP verification fails before user lookup or creation', async () => {
    const getUserByEmail = jest.fn();
    const createUser = jest.fn();
    const deps: RegisterWithEmailOtpDeps = {
      consumeOtp: async () => {
        throw new functions.https.HttpsError('permission-denied', 'Invalid verification code.');
      },
      getUserByEmail,
      createUser,
    };

    await expect(
      executeRegisterWithEmailOtp(deps, {
        email: 'user@bhromon.fun',
        otp: '000000',
        password: 'strongPassword9',
      }),
    ).rejects.toMatchObject({ code: 'permission-denied' });
    expect(getUserByEmail).not.toHaveBeenCalled();
    expect(createUser).not.toHaveBeenCalled();
  });

  it('accepts emulator OTP code 777777 when running in emulator mode', async () => {
    const consumeOtp = jest.fn();
    const deps: RegisterWithEmailOtpDeps = {
      emulator: true,
      consumeOtp,
      getUserByEmail: async () => {
        throw userNotFoundError();
      },
      createUser: async () => ({ uid: 'uid-emu' }),
    };

    const result = await executeRegisterWithEmailOtp(deps, {
      email: 'emu@bhromon.fun',
      otp: '777777',
      password: 'strongPassword9',
    });

    expect(result).toEqual({ success: true, uid: 'uid-emu' });
    expect(consumeOtp).not.toHaveBeenCalled();
  });
});
