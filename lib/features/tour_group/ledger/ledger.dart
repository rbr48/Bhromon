/// Cohesive Trip & Group Ledger sub-domain entrypoint for `tour_group`.
///
/// Re-exports the Expense/Fund/MFS models, pure ledger & analytics engines,
/// PDF statement generator, and presentation screens/sheets so callers and
/// tests can import a single bounded module.
library;

// Data / PDF statement generation
export '../data/monthly_ledger_pdf.dart';

// Domain models
export '../domain/models/expense_models.dart';

// Domain services & pure ledger engines
export '../domain/services/debt_simplifier.dart';
export '../domain/services/fund_analytics.dart';
export '../domain/services/mfs_sms_parser.dart';
export '../domain/services/trip_ledger_engine.dart';

// Presentation screens & sheets
export '../presentation/monthly_ledger_pdf_export.dart';
export '../presentation/pages/expense_ledger_screen.dart';
export '../presentation/widgets/fund/expense_editor.dart';
export '../presentation/widgets/fund/fund_sheets.dart';
export '../presentation/widgets/fund/mfs_settlement_sheet.dart';
