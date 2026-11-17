import 'package:flutter/material.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';

/// Builds an [InputDecoration] for borderless inline composer fields that
/// explicitly disables the global [InputDecorationTheme] fill and outlines.
InputDecoration borderlessComposerDecoration({
  String? hintText,
  TextStyle? hintStyle,
  String? counterText,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(vertical: 4),
}) {
  return InputDecoration(
    counterText: counterText,
    hintText: hintText,
    hintStyle: hintStyle,
    filled: false,
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: contentPadding,
  );
}

/// Compact "Aa" formatting-toolbar toggle shared across chat composers.
class ComposerFormatButton extends StatelessWidget {
  const ComposerFormatButton({
    super.key,
    required this.active,
    required this.inactiveColor,
    required this.onPressed,
  });

  final bool active;
  final Color inactiveColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.translate('format_toolbar_toggle');
    return Semantics(
      label: label,
      button: true,
      child: SizedBox(
        width: 38,
        height: 38,
        child: IconButton(
          tooltip: label,
          padding: EdgeInsets.zero,
          icon: Text(
            'Aa',
            style: TextStyle(
              color: active ? AppColors.mintGreen : inactiveColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: -0.5,
              decoration:
                  active ? TextDecoration.underline : TextDecoration.none,
              decorationColor: AppColors.mintGreen,
            ),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Shared two-row full-width message composer shell.
///
/// Places [textField] across the full width of the panel on top and a compact
/// action bar below with [leadingActions] on the left and [trailingAction] on
/// the right.
class ChatComposerCard extends StatelessWidget {
  const ChatComposerCard({
    super.key,
    required this.backgroundColor,
    required this.textField,
    required this.leadingActions,
    required this.trailingAction,
    this.outerPadding = const EdgeInsets.fromLTRB(4, 4, 4, 6),
  });

  final Color backgroundColor;
  final Widget textField;
  final List<Widget> leadingActions;
  final Widget trailingAction;
  final EdgeInsetsGeometry outerPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: outerPadding,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
              child: textField,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 8, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ...leadingActions,
                  const Spacer(),
                  trailingAction,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
