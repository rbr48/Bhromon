import 'package:flutter/material.dart';

import '../../../../../core/localization/app_localizations.dart';
import '../../../../../core/theme/colors.dart';
import '../../../../../core/theme/forest_palette.dart';
import '../../../../chat/presentation/widgets/chat_formatting_toolbar.dart';

/// A multi-line field for study text. It takes the same settings as a [TextField]. Under it is the markup
/// button, "Aa", which shows the chat's formatting menu above the text, without the table button. The text is
/// markdown, so a table written in it renders wherever study text is shown.
class StudyTextField extends StatefulWidget {
  const StudyTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.autofocus = false,
    this.minLines = 2,
    this.maxLines = 6,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final bool autofocus;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  State<StudyTextField> createState() => _StudyTextFieldState();
}

class _StudyTextFieldState extends State<StudyTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _showFormatting = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showFormatting)
          ChatFormattingToolbar(
            controller: widget.controller,
            focusNode: _focusNode,
            showTable: false,
            onClose: () => setState(() => _showFormatting = false),
          ),
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          style: TextStyle(color: palette.text),
          decoration: widget.decoration,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _MarkupButton(
            active: _showFormatting,
            onPressed: () => setState(() => _showFormatting = !_showFormatting),
          ),
        ),
      ],
    );
  }
}

/// The "Aa" button that shows or hides the markup menu, drawn as the chat composers draw it.
class _MarkupButton extends StatelessWidget {
  const _MarkupButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final color = active ? AppColors.mintGreen : context.forest.text70;
    return Semantics(
      label: l10n.translate('format_toolbar_toggle'),
      button: true,
      child: IconButton(
        tooltip: l10n.translate('format_toolbar_toggle'),
        onPressed: onPressed,
        icon: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(4),
            color: active
                ? AppColors.mintGreen.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Text(
            'Aa',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
