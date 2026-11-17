import * as functions from 'firebase-functions/v1';
import {
  executeResetPasswordWithOtp,
  ResetPasswordWithOtpDeps,
} from '../resetPasswordWithOtp';

function userNotFoundError(): Error & { code: string } {
  const err = new Error('User not found') as Error & { code: string };
  err.code = 'auth/user-not-found';
  return err;
}

describe('executeResetPasswordWithOtp', () => {
  it('consumes OTP first and updates password with emailVerified=true', async () => {
    const calls: string[] = [];
    const deps: ResetPasswordWithOtpDeps = {
      consumeOtp: async (email, code) => {
        calls.push(`consume:${email}:${code}`);
      },
      getUserByEmail: async (email) => {
        calls.push(`lookup:${email}`);
        return { uid: 'uid-42', disabled: false };
      },
      updateUser: async (uid, props) => {
        calls.push(`update:${uid}:${props.password}:${props.emailVerified}`);
        return { uid };
      },
    };

    const result = await executeResetPasswordWithOtp(deps, {
      email: '  Explorer@Bhromon.Fun ',
      otp: ' 654321 ',
      password: 'newpassword123',
    });

    expect(result).toEqual({ success: true, uid: 'uid-42' });
    expect(calls).toEqual([
      'consume:explorer@bhromon.fun:654321',
      'lookup:explorer@bhromon.fun',
      'update:uid-42:newpassword123:true',
    ]);
  });

  it('rejects unknown account after consuming OTP to prevent pre-OTP enumeration', async () => {
    const calls: string[] = [];
    const deps: ResetPasswordWithOtpDeps = {
      consumeOtp: async (email, code) => {
        calls.push(`consume:${email}:${code}`);
      },
      getUserByEmail: async () => {
        calls.push('lookup');
        throw userNotFoundError();
      },
      updateUser: async () => {
        throw new Error('Should not update missing account');
      },
    };

    await expect(
      executeResetPasswordWithOtp(deps, {
        email: 'missing@bhromon.fun',
        otp: '654321',
        password: 'newpassword123',
      }),
    ).rejects.toMatchObject({
      code: 'not-found',
    });
    expect(calls).toEqual(['consume:missing@bhromon.fun:654321', 'lookup']);
  });

  it('rejects disabled accounts without updating password', async () => {
    let updated = false;
    const deps: ResetPasswordWithOtpDeps = {
      consumeOtp: async () => {},
      getUserByEmail: async () => ({ uid: 'uid-locked', disabled: true }),
      updateUser: async () => {
        updated = true;
        return { uid: 'uid-locked' };
      },
    };

    await expect(
      executeResetPasswordWithOtp(deps, {
        email: 'locked@bhromon.fun',
        otp: '654321',
        password: 'newpassword123',
      }),
    ).rejects.toMatchObject({
      code: 'permission-denied',
    });
    expect(updated).toBe(false);
  });

  it('validates input before consuming OTP', async () => {
    let consumed = false;
    const deps: ResetPasswordWithOtpDeps = {
      consumeOtp: async () => {
        consumed = true;
      },
      getUserByEmail: async () => ({ uid: 'u1' }),
      updateUser: async (uid) => ({ uid }),
    };

    await expect(
      executeResetPasswordWithOtp(deps, {
        email: 'user@bhromon.fun',
        otp: '123',
        password: 'newpassword123',
      }),
    ).rejects.toBeInstanceOf(functions.https.HttpsError);
    expect(consumed).toBe(false);
  });

  it('accepts emulator bypass code 777777 when running in emulator', async () => {
    let consumed = false;
    const deps: ResetPasswordWithOtpDeps = {
      consumeOtp: async () => {
        consumed = true;
      },
      getUserByEmail: async () => ({ uid: 'uid-emu' }),
      updateUser: async (uid) => ({ uid }),
      emulator: true,
    };

    const result = await executeResetPasswordWithOtp(deps, {
      email: 'emu@bhromon.fun',
      otp: '777777',
      password: 'newpassword123',
    });

    expect(result).toEqual({ success: true, uid: 'uid-emu' });
    expect(consumed).toBe(false);
  });
});
