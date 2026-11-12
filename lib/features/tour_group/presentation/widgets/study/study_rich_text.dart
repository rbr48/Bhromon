import 'package:flutter/material.dart';

import '../../../../chat/presentation/widgets/chat_rich_text.dart';

/// Study text as it is shown. It is markdown, the same as a chat message, so a table written in it renders as
/// a table, and the emphasis and lists in it render too. A text without markdown looks the same as plain text.
/// Its tables show no column totals: a column of prices or quantities is not money to add up.
class StudyRichText extends StatelessWidget {
  const StudyRichText(this.text, {super.key, this.style});

  final String text;

  /// The style of the text. The table and the emphasis are drawn from it.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ChatRichText(
      text: text,
      baseStyle: style,
      showColumnTotals: false,
    );
  }
}
