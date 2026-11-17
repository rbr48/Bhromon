import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bhromon/core/errors/failures.dart';
import 'package:bhromon/core/localization/app_localizations.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:bhromon/features/auth/presentation/cubit/auth_state.dart';
import 'package:bhromon/features/auth/presentation/pages/login_screen.dart';

class _FakeAuthCubit extends Cubit<AuthState> implements AuthCubit {
  _FakeAuthCubit(super.initialState);

  final List<({String email, String password})> emailPasswordCalls = [];
  final List<String> signUpOtpEmails = [];
  final List<({String email, String password, String otp, String? displayName})>
      registerCalls = [];
  int googleCalls = 0;

  @override
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    emailPasswordCalls.add((email: email, password: password));
  }

  @override
  Future<void> requestSignUpOtp(String email) async {
    signUpOtpEmails.add(email);
    emit(AuthOtpSent(email));
  }

  @override
  Future<void> registerWithEmailOtp({
    required String email,
    required String password,
    required String otp,
    String? displayName,
  }) async {
    registerCalls.add((
      email: email,
      password: password,
      otp: otp,
      displayName: displayName,
    ));
  }

  @override
  Future<void> signInWithGoogle() async {
    googleCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp(_FakeAuthCubit authCubit) {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
    ],
  );

  return BlocProvider<AuthCubit>.value(
    value: authCubit,
    child: MaterialApp.router(
      locale: const Locale('en'),
      supportedLocales: const [Locale('en'), Locale('bn')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('renders Google and Email sign-in options on initial load',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = _FakeAuthCubit(const Unauthenticated());
    addTearDown(cubit.close);

    await tester.pumpWidget(_buildTestApp(cubit));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in with Email'), findsOneWidget);
    expect(find.text('Create account with Email'), findsOneWidget);
    expect(find.byKey(const Key('login_email_field')), findsNothing);
  });

  testWidgets(
      'validates and completes Email + Password sign-up via 6-digit OTP',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = _FakeAuthCubit(const Unauthenticated());
    addTearDown(cubit.close);

    await tester.pumpWidget(_buildTestApp(cubit));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('login_open_create_account_button')),
    );
    await tester.tap(find.byKey(const Key('login_open_create_account_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('signup_email_field')),
      'newuser@bhromon.fun',
    );
    await tester.enterText(
      find.byKey(const Key('signup_password_field')),
      '123',
    );
    await tester.ensureVisible(find.byKey(const Key('signup_send_otp_button')));
    await tester.tap(find.byKey(const Key('signup_send_otp_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your name.'), findsOneWidget);
    expect(
      find.text('Password must be at least 6 characters.'),
      findsOneWidget,
    );
    expect(cubit.signUpOtpEmails, isEmpty);

    await tester.enterText(
      find.byKey(const Key('signup_name_field')),
      'Rana Explorer',
    );
    await tester.enterText(
      find.byKey(const Key('signup_password_field')),
      'StrongPass123',
    );
    await tester.ensureVisible(find.byKey(const Key('signup_send_otp_button')));
    await tester.tap(find.byKey(const Key('signup_send_otp_button')));
    await tester.pumpAndSettle();

    expect(cubit.signUpOtpEmails, ['newuser@bhromon.fun']);
    expect(find.byKey(const Key('signup_otp_field')), findsOneWidget);
    expect(
      find.text(
          'Enter the 6-digit verification code sent to newuser@bhromon.fun.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('signup_otp_field')),
      '482910',
    );
    await tester.ensureVisible(
      find.byKey(const Key('signup_verify_otp_button')),
    );
    await tester.tap(find.byKey(const Key('signup_verify_otp_button')));
    await tester.pumpAndSettle();

    expect(cubit.registerCalls, [
      (
        email: 'newuser@bhromon.fun',
        password: 'StrongPass123',
        otp: '482910',
        displayName: 'Rana Explorer',
      ),
    ]);

    cubit.emit(const AuthError(
      'otp mismatch',
      reason: AuthFailureReason.otpInvalid,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Invalid verification code. Please check and try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('signup_otp_field')), findsOneWidget);
  });

  testWidgets('validates email and password before dispatching cubit sign-in',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = _FakeAuthCubit(const Unauthenticated());
    addTearDown(cubit.close);

    await tester.pumpWidget(_buildTestApp(cubit));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign in with Email'));
    await tester.tap(find.text('Sign in with Email'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('login_email_submit_button')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      'not-an-email',
    );
    await tester.ensureVisible(
      find.byKey(const Key('login_email_submit_button')),
    );
    await tester.tap(find.byKey(const Key('login_email_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    expect(find.text('Please enter your password.'), findsOneWidget);
    expect(cubit.emailPasswordCalls, isEmpty);
  });

  testWidgets(
      'submits valid email/password credentials and displays invalidCredentials error',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = _FakeAuthCubit(const Unauthenticated());
    addTearDown(cubit.close);

    await tester.pumpWidget(_buildTestApp(cubit));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign in with Email'));
    await tester.tap(find.text('Sign in with Email'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      '  tester@bhromon.fun  ',
    );
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      'BhromonTest123!',
    );
    await tester.ensureVisible(
      find.byKey(const Key('login_email_submit_button')),
    );
    await tester.tap(find.byKey(const Key('login_email_submit_button')));
    await tester.pumpAndSettle();

    expect(cubit.emailPasswordCalls, [
      (email: 'tester@bhromon.fun', password: 'BhromonTest123!'),
    ]);

    cubit.emit(const AuthError(
      'firebase invalid-credential',
      reason: AuthFailureReason.invalidCredentials,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(
        'Invalid email or password. Please check your credentials and try again.',
      ),
      findsOneWidget,
    );
  });
}
