# Implementation Plan: Itinerary Printable PDF, Burn-Rate Budget Alerts & Route Checkpoint Overlay

## Objective
Implement Roadmap Sprints 9 & 10 items:
- **Sprint 9 (Travel and Live Journey)**:
  - Task 9.4: Multi-stop Itinerary Printable PDF using `bangla_pdf` with custom Bangla typography and day-by-day itinerary tables.
  - Task 9.3: Route checkpoints & waypoints overlay on Offline Map (`offline_map_viewer_screen.dart`).
- **Sprint 10 (Ledger and FinOps)**:
  - Task 10.3: Burn-rate threshold alerts (`normal`, `caution` at ≥80% or projected overage, `critical` at ≥100%) in `fund_analytics.dart` and `expense_ledger_screen.dart`.
- **Release**: Monotonic version bump to `1.8.149+203`, unit test suite verification, GitHub PR with 100% green CI gate, and production deployments.

---

## Atomic Tasks

### Phase 1: Sprint 10 — Burn-Rate Alerts & Budget Thresholds
- [ ] **Task 1.1: BurnRateAlert Model & Logic in `fund_analytics.dart`**
  - Add `BurnRateAlert` enum (`normal`, `caution`, `critical`) to `fund_analytics.dart`.
  - Add `alertLevel` getter to `FundReport` and `BudgetLine`.
  - Trigger `caution` if spent ratio ≥ 0.80 or if projected spend exceeds budget.
  - Trigger `critical` if spent ratio ≥ 1.00 (`isOverBudget`).
  - Unit test in `test/features/tour_group/fund_burn_rate_test.dart`.

- [ ] **Task 1.2: UI Warnings in `expense_ledger_screen.dart`**
  - Display caution/critical banner badge in the Budget vs Spent section.
  - Show warning accent colors (amber for caution, red for critical).
  - Add localized strings in `app_localizations.dart` / translation keys.

### Phase 2: Sprint 9 — Multi-Stop Itinerary PDF
- [ ] **Task 2.1: Itinerary PDF Generator (`itinerary_pdf.dart`)**
  - Create `lib/features/tour_group/data/itinerary_pdf.dart` using `bangla_pdf`.
  - Render tour header (destination summary, dates, duration, style, total members).
  - Render stops breakdown table (order, destination, arrival, departure, nights, notes).
  - Render transport legs and route checkpoints (modes, distance estimates, checkpoint stops).
  - Render packing checklist summary if available.
  - Unit test in `test/features/tour_group/itinerary_pdf_test.dart`.

- [ ] **Task 2.2: Itinerary PDF Export Wire-up (`itinerary_pdf_export.dart`)**
  - Create `lib/features/tour_group/presentation/itinerary_pdf_export.dart`.
  - Add "Export Itinerary PDF" button in `journey_tracker_screen.dart` and `itinerary_editor.dart`.
  - Support cross-platform downloading on Web (`kIsWeb`) and share sheet on Mobile (`share_plus`).

### Phase 3: Sprint 9 — Route Checkpoint Overlay on Offline Map
- [ ] **Task 3.1: Route & Checkpoint Markers in `offline_map_viewer_screen.dart`**
  - Read `RoutePlan.of(group)` when viewing a tour.
  - Display route checkpoints and stops as map markers with icons and names.
  - Tap marker to view checkpoint details (type, leg, notes).

### Phase 4: Automated Testing, Release & CI Green Gate
- [ ] **Task 4.1: Automated Verification & Monotonic Version Bump**
  - Run `flutter analyze` and all unit tests.
  - Monotonically increment version in `pubspec.yaml` to `1.8.149+203`.
- [ ] **Task 4.2: PR Creation & Merge**
  - Push branch, open PR via `gh pr create --base main`.
  - Wait for all GitHub Actions CI checks to pass green.
  - Merge PR, deploy web to Firebase Hosting and release APK to Hostinger VPS.
