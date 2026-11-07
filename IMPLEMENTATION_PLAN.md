# Implementation Plan: Desktop Photo Carousel Navigation & Mouse Dragging

## Objective
Enable seamless photo navigation in Moments (`InstafeedCarousel` and `InstafeedImageViewerModal`) on desktop web:
1. Allow mouse click-and-drag horizontal swiping.
2. Provide prominent, elegant Left and Right chevron navigation buttons (`<` and `>`).
3. Make the bottom dot indicators clickable.
4. Support keyboard arrow navigation.

## Tasks
- [x] **Task 1: Enable Mouse & Trackpad Drag Scrolling in `InstafeedCarousel`**
  - Wrap `PageView.builder` in a `ScrollConfiguration` enabling `PointerDeviceKind.mouse`, `trackpad`, `touch`, `stylus`.
- [x] **Task 2: Add Desktop Next & Previous Navigation Arrow Buttons in `InstafeedCarousel`**
  - Add `CarouselNavButton` with hover highlights (`AppColors.mintGreen`).
  - Show Left chevron when `_currentIndex > 0`.
  - Show Right chevron when `_currentIndex < imageUrls.length - 1`.
  - Wire buttons to `_pageCtrl.previousPage` and `_pageCtrl.nextPage`.
- [x] **Task 3: Make Pagination Dot Indicators Clickable**
  - Wrap dots in `GestureDetector`/`MouseRegion` to jump directly to any photo (`animateToPage(index)`).
- [x] **Task 4: Add Navigation Buttons & Mouse Drag to `InstafeedImageViewerModal`**
  - Enable mouse drag, prominent 46px `<` / `>` buttons, and keyboard Arrow Left/Right/Escape shortcuts in the fullscreen photo viewer.
- [x] **Task 5: Write Automated Tests**
  - Created `test/features/tour_group/presentation/widgets/instafeed/instafeed_carousel_test.dart` (5 tests passing).
  - Created `test/features/tour_group/presentation/widgets/instafeed/instafeed_image_viewer_modal_test.dart` (3 tests passing).
- [x] **Task 6: Verification, Web Deployment & PR Workflow**
  - Run `dart format`, `dart analyze`, and `flutter test`.
  - Build and deploy to Firebase Hosting (`app.bhromon.fun`).
  - Create feature branch, open PR, merge into `main`, and verify CI.
