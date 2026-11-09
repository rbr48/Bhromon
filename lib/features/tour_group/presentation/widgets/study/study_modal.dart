import 'package:flutter/material.dart';

import '../../../../../core/theme/forest_palette.dart';

/// Opens a study form or menu as a card in the middle of the screen, the way the tip editor opens.
/// Every study modal uses it, so they all look the same on every screen size. The card is at most 560 wide
/// and 90% of the height that is free above the keyboard, and it closes on a tap outside unless
/// [barrierDismissible] is false. Returns what the modal pops with, or null when it is dismissed.
Future<T?> showStudyModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final free = MediaQuery.sizeOf(dialogContext).height -
          MediaQuery.viewInsetsOf(dialogContext).bottom;
      return Dialog(
        backgroundColor: dialogContext.forest.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: free * 0.9),
          child: builder(dialogContext),
        ),
      );
    },
  );
}
