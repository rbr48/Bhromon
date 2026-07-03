import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ─── Brand colours (mirrors login_screen.dart) ────────────────────────────────
const Color _kBg = Color(0xFF050C08);
const Color _kCardBg = Color(0xFF0D1A12);
const Color _kFieldBg = Color(0xFF0A140D);
const Color _kBorder = Color(0xFF1E3A26);
const Color _kGreen = Color(0xFF52B788);
const Color _kRed = Color(0xFFE63946);
const Color _kWhite = Color(0xFFECF0F1);
const Color _kWhite54 = Color(0x8AECF0F1);
const Color _kWhite30 = Color(0x4DECF0F1);

/// Multi-step account deletion flow.
///
/// Step 1 — Warning screen explaining permanent consequences.
/// Step 2 — Confirmation field (user must type "DELETE").
/// Step 3 — Loading / success / error state.
///
/// On success the Cloud Function `gdprDeleteUser` is called, the local Firebase
/// Auth session is signed out, and the app navigates back to `/`.
class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  int _step = 0; // 0 = warning, 1 = confirm, 2 = loading/done
  final _confirmController = TextEditingController();
  String? _errorMessage;
  bool _isDeleting = false;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _submitDeletion() async {
    if (_confirmController.text.trim() != 'DELETE') {
      setState(() => _errorMessage = 'Type DELETE (uppercase) to confirm.');
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
      _step = 2;
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-south1');
      final callable = functions.httpsCallable('gdprDeleteUser');
      await callable.call<void>(<String, dynamic>{});

      // Sign out the now-deleted account
      await FirebaseAuth.instance.signOut();

      if (mounted) {
        // Navigate to root and show a confirmation snackbar
        context.go('/');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account has been permanently deleted.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _step = 1;
          _errorMessage =
              e.message ?? 'Deletion failed. Please try again later.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _step = 1;
          _errorMessage =
              'An unexpected error occurred. Please try again later.';
        });
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCardBg,
        foregroundColor: _kWhite,
        title: const Text(
          'Delete Account',
          style: TextStyle(color: _kWhite, fontWeight: FontWeight.w600),
        ),
        leading: _step == 2 && _isDeleting
            ? null
            : const BackButton(color: _kWhite),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return switch (_step) {
      0 => _WarningStep(onContinue: () => setState(() => _step = 1)),
      1 => _ConfirmStep(
          controller: _confirmController,
          errorMessage: _errorMessage,
          onSubmit: _submitDeletion,
          onCancel: () => Navigator.pop(context),
        ),
      _ => _isDeleting
          ? const _LoadingStep()
          : const _ErrorStep(), // shouldn't reach here
    };
  }
}

// ─── Step widgets ─────────────────────────────────────────────────────────────

class _WarningStep extends StatelessWidget {
  const _WarningStep({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: _kRed, size: 48),
          const SizedBox(height: 20),
          const Text(
            'This action is permanent.',
            style: TextStyle(
              color: _kWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Deleting your account will permanently remove:',
            style: TextStyle(color: _kWhite54, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...[
            'Your explorer profile and trust score',
            'All trip logs, photos, and audio notes',
            'Your map pins and contributions',
            'Chat history and connections',
            'Purchased guides and premium content',
          ].map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.remove_circle_outline,
                      color: _kRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(color: _kWhite, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kCardBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kRed.withOpacity(.4)),
            ),
            child: const Text(
              'This cannot be undone. Your username may become available to '
              'other users immediately.',
              style: TextStyle(color: _kWhite54, fontSize: 13),
            ),
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kRed,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onContinue,
            child: const Text(
              'I understand, continue',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _kWhite,
              side: const BorderSide(color: _kBorder),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel, keep my account'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ConfirmStep extends StatelessWidget {
  const _ConfirmStep({
    required this.controller,
    required this.errorMessage,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirm account deletion',
            style: TextStyle(
              color: _kWhite,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'To confirm, type DELETE in the box below.',
            style: TextStyle(color: _kWhite54, fontSize: 15),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            style: const TextStyle(color: _kWhite),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Type DELETE here',
              hintStyle: const TextStyle(color: _kWhite30),
              filled: true,
              fillColor: _kFieldBg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _kRed.withOpacity(.8)),
              ),
              errorText: errorMessage,
              errorStyle: const TextStyle(color: _kRed),
            ),
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _kRed,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: onSubmit,
            child: const Text(
              'Permanently Delete My Account',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: _kWhite54,
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _LoadingStep extends StatelessWidget {
  const _LoadingStep();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
          ),
          SizedBox(height: 20),
          Text(
            'Deleting your account…\nThis may take a moment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _kWhite54, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _ErrorStep extends StatelessWidget {
  const _ErrorStep();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'An error occurred.',
        style: TextStyle(color: _kRed),
      ),
    );
  }
}
