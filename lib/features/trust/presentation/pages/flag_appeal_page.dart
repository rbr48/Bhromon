import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/trust_bloc.dart';
import '../bloc/trust_event.dart';
import '../bloc/trust_state.dart';

// ─── Brand colours ────────────────────────────────────────────────────────────
const Color _kBg = Color(0xFF050C08);
const Color _kCardBg = Color(0xFF0D1A12);
const Color _kFieldBg = Color(0xFF0A140D);
const Color _kBorder = Color(0xFF1E3A26);
const Color _kGreen = Color(0xFF52B788);
const Color _kGold = Color(0xFFF4A261);
const Color _kWhite = Color(0xFFECF0F1);
const Color _kWhite54 = Color(0x8AECF0F1);
const Color _kWhite30 = Color(0x4DECF0F1);

/// Minimum character count required for an appeal justification.
const int _kMinJustificationLength = 50;

/// Flag-appeal submission form.
///
/// Route params:
///   - [targetId]   – The Firestore document ID of the flagged content.
///   - [targetType] – Human-readable content type (e.g. "trip_log", "pin").
///
/// The page reads these from its constructor and displays them as read-only
/// information before letting the user write a justification. On success it
/// pops and shows a confirmation banner.
class FlagAppealPage extends StatefulWidget {
  const FlagAppealPage({
    super.key,
    required this.targetId,
    required this.targetType,
  });

  final String targetId;
  final String targetType;

  @override
  State<FlagAppealPage> createState() => _FlagAppealPageState();
}

class _FlagAppealPageState extends State<FlagAppealPage> {
  final _formKey = GlobalKey<FormState>();
  final _justificationController = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _justificationController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;

    context.read<TrustBloc>().add(
          SubmitAppealEvent(
            targetId: widget.targetId,
            justification: _justificationController.text.trim(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TrustBloc, TrustState>(
      listenWhen: (prev, curr) => prev.appealStatus != curr.appealStatus,
      listener: (context, state) {
        if (state.appealStatus == AppealStatus.success && !_submitted) {
          _submitted = true;
          // Show success and pop after a short delay so the user sees the state
          Future.delayed(const Duration(milliseconds: 300), () {
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                    '✅ Appeal submitted. Our team will review it within 48 hours.',
                  ),
                  backgroundColor: _kGreen.withValues(alpha: .9),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          });
        } else if (state.appealStatus == AppealStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'Failed to submit appeal.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      builder: (context, state) {
        final isSubmitting = state.appealStatus == AppealStatus.submitting;

        return Scaffold(
          backgroundColor: _kBg,
          appBar: AppBar(
            backgroundColor: _kCardBg,
            foregroundColor: _kWhite,
            title: const Text(
              'Appeal Flag',
              style: TextStyle(
                color: _kWhite,
                fontWeight: FontWeight.w600,
                letterSpacing: .4,
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──────────────────────────────────────────────
                  const Text(
                    'Contest a content flag',
                    style: TextStyle(
                      color: _kWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'If you believe your content was flagged in error, '
                    'explain why below. Our trust team reviews all appeals '
                    'within 48 hours.',
                    style: TextStyle(color: _kWhite54, fontSize: 14, height: 1.5),
                  ),

                  const SizedBox(height: 28),

                  // ── Read-only info card ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _kCardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Column(
                      children: [
                        _InfoRow(
                          label: 'Content type',
                          value: _formatContentType(widget.targetType),
                        ),
                        const Divider(color: _kBorder, height: 20),
                        _InfoRow(
                          label: 'Content ID',
                          value: widget.targetId,
                          isMonospace: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Justification field ─────────────────────────────────
                  const _SectionLabel(
                    label: 'Your justification',
                    hint: 'Minimum $_kMinJustificationLength characters',
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _justificationController,
                    enabled: !isSubmitting,
                    maxLength: 2000,
                    maxLines: 8,
                    style: const TextStyle(color: _kWhite, fontSize: 14),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText:
                          'Explain why this content should not have been flagged. '
                          'Include any relevant context about the content and why '
                          'it complies with Bhromon community guidelines…',
                      hintStyle: const TextStyle(color: _kWhite30, fontSize: 13),
                      filled: true,
                      fillColor: _kFieldBg,
                      counterStyle: const TextStyle(color: _kWhite30),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _kGreen),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: Colors.redAccent.withValues(alpha: .7)),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      errorStyle: const TextStyle(color: Colors.redAccent),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please provide a justification.';
                      }
                      if (value.trim().length < _kMinJustificationLength) {
                        return 'Justification must be at least '
                            '$_kMinJustificationLength characters '
                            '(currently ${value.trim().length}).';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // ── Character hint ──────────────────────────────────────
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _justificationController,
                    builder: (_, val, __) {
                      final len = val.text.trim().length;
                      final enough = len >= _kMinJustificationLength;
                      return Text(
                        '$len / $_kMinJustificationLength characters minimum',
                        style: TextStyle(
                          color: enough ? _kGreen : _kGold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // ── Submit button ───────────────────────────────────────
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kGreen,
                      foregroundColor: const Color(0xFF050C08),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isSubmitting ? null : () => _submit(context),
                    child: isSubmitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF050C08),
                              ),
                            ),
                          )
                        : const Text(
                            'Submit Appeal',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),

                  const SizedBox(height: 8),

                  // ── Disclaimer ──────────────────────────────────────────
                  const Text(
                    'Frivolous or bad-faith appeals may negatively affect your '
                    'trust score.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _kWhite30, fontSize: 12),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Converts a snake_case content type to a readable label.
  String _formatContentType(String raw) =>
      raw.replaceAll('_', ' ').toUpperCase();
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.isMonospace = false,
  });

  final String label;
  final String value;
  final bool isMonospace;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(
              color: _kWhite54,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: _kWhite,
              fontSize: 13,
              fontFamily: isMonospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _kWhite,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          hint,
          style: const TextStyle(color: _kWhite30, fontSize: 12),
        ),
      ],
    );
  }
}
