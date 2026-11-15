import 'package:flutter/material.dart';

import '../theme/forest_palette.dart';

/// The width from which a list of records is drawn as a table. Narrower than this the
/// screen keeps its list of cards.
const double kDataTableMinWidth = 640;

/// Whether a list of records has room to be a table here. Inside the desktop shell the
/// width is the page's own column, not the window.
bool showsDataTable(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDataTableMinWidth;

/// One column of a [DataListTable]. A column with a [width] is fixed; the others share the
/// rest of the row by [flex].
class DataListColumn {
  const DataListColumn(this.label, {this.flex = 1, this.width});

  final String label;
  final int flex;
  final double? width;
}

/// One row of a [DataListTable]: a cell per column, an optional tap, and an optional
/// widget at the end (a menu or a button).
class DataListRow {
  const DataListRow({
    required this.cells,
    this.onTap,
    this.trailing,
    this.key,
  });

  final List<Widget> cells;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Key? key;
}

/// A table of records for a wide screen: a header, and one compact row per record, in one
/// card. A phone shows the same records as a list of cards; on a desktop window those cards
/// stretch to one line each with most of the row empty, and the columns cannot be compared.
class DataListTable extends StatelessWidget {
  const DataListTable({
    super.key,
    required this.columns,
    required this.rows,
    this.trailingWidth = 48,
  });

  final List<DataListColumn> columns;
  final List<DataListRow> rows;

  /// The room kept at the end of each row for [DataListRow.trailing].
  final double trailingWidth;

  Widget _cell(DataListColumn column, Widget child) {
    final padded = Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );
    return column.width != null
        ? SizedBox(width: column.width, child: padded)
        : Expanded(flex: column.flex, child: padded);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.forest;
    final headerStyle = TextStyle(
      color: palette.text54,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Card(
      color: palette.card,
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                for (final column in columns)
                  _cell(
                    column,
                    Text(column.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: headerStyle),
                  ),
                SizedBox(width: trailingWidth),
              ],
            ),
          ),
          for (final row in rows) ...[
            Divider(height: 1, color: palette.divider10),
            InkWell(
              key: row.key,
              onTap: row.onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  child: Row(
                    children: [
                      for (var i = 0; i < columns.length; i++)
                        _cell(columns[i], row.cells[i]),
                      SizedBox(
                        width: trailingWidth,
                        child: row.trailing,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
