import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../chat/presentation/widgets/chat_composer_card.dart';
import '../../../../chat/presentation/widgets/chat_formatting_toolbar.dart';

import 'study_text_field.dart';

/// The message box at the foot of a study conversation, drawn as a full-width two-row composer:
/// the typing area spans the top row, while the bottom strip holds the "Aa" markup button, an
/// optional chapter/page button ([onDetails]), and the send button on the right. The "Aa" button
/// shows the chat's formatting menu without the table button.
class StudyChatComposer extends StatefulWidget {
  const StudyChatComposer({
    super.key,
    required this.controller,
    required this.hint,
    required this.sending,
    required this.onSend,
    this.onDetails,
    this.detailsTooltip,
  });

  final TextEditingController controller;
  final String hint;

  /// Whether a message is being saved. The box stays, but nothing can be sent until it is done.
  final bool sending;
  final VoidCallback onSend;

  /// Opens the chapter and page choices. Null leaves that button out.
  final VoidCallback? onDetails;
  final String? detailsTooltip;

  @override
  State<StudyChatComposer> createState() => _StudyChatComposerState();
}

class _StudyChatComposerState extends State<StudyChatComposer> {
  final FocusNode _focusNode = FocusNode();
  bool _showFormatting = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleFormatting() =>
      setState(() => _showFormatting = !_showFormatting);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.forest;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showFormatting)
            ChatFormattingToolbar(
              controller: widget.controller,
              focusNode: _focusNode,
              showTable: false,
              onClose: () => setState(() => _showFormatting = false),
            ),
          ChatComposerCard(
            backgroundColor: palette.inset26,
            textField: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: TextStyle(
                color: palette.text,
                fontSize: 16,
                height: 1.38,
                letterSpacing: 0.05,
                fontFamily: 'NotoSansBengali',
                fontFamilyFallback: const [
                  'HindSiliguri',
                  'Roboto',
                  'sans-serif',
                ],
              ),
              decoration: borderlessComposerDecoration(
                counterText: '',
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: palette.text54,
                  fontSize: 15,
                  fontFamily: 'NotoSansBengali',
                  fontFamilyFallback: const [
                    'HindSiliguri',
                    'Roboto',
                    'sans-serif',
                  ],
                ),
              ),
            ),
            leadingActions: [
              StudyMarkupButton(
                active: _showFormatting,
                onPressed: widget.sending ? null : _toggleFormatting,
              ),
              if (widget.onDetails != null)
                IconButton(
                  tooltip: widget.detailsTooltip,
                  constraints:
                      const BoxConstraints(minWidth: 38, minHeight: 38),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.menu_book_outlined,
                      color: palette.text70, size: 21),
                  onPressed: widget.sending ? null : widget.onDetails,
                ),
            ],
            trailingAction: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) {
                final canSend = !widget.sending && value.text.trim().isNotEmpty;
                return IconButton(
                  tooltip: l10n.translate('tour_send'),
                  constraints:
                      const BoxConstraints(minWidth: 38, minHeight: 38),
                  padding: EdgeInsets.zero,
                  icon: widget.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: AppColors.mintGreen,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          color: canSend ? palette.accentText : palette.text54,
                        ),
                  onPressed: canSend ? widget.onSend : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
