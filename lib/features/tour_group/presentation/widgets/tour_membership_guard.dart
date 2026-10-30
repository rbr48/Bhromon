import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../data/tour_group_repository.dart';

/// Closes a tour's screens as soon as the signed-in user is no longer a member
/// of that tour. The tour is cleared from this device, and the user goes to the
/// Tours hub, which asks them to join or create a tour when none is left.
class TourMembershipGuard extends StatefulWidget {
  const TourMembershipGuard({
    super.key,
    required this.tourId,
    required this.child,
    this.repository,
  });

  final String tourId;
  final Widget child;

  /// Lets tests supply a repository that does not touch Firebase.
  final TourGroupRepository? repository;

  @override
  State<TourMembershipGuard> createState() => _TourMembershipGuardState();
}

class _TourMembershipGuardState extends State<TourMembershipGuard> {
  late final TourGroupRepository _repository =
      widget.repository ?? TourGroupRepository();
  StreamSubscription<bool>? _membership;

  // Removal counts only after the server has confirmed membership once, so a
  // membership row the app cannot match never closes a tour the user is in.
  bool _confirmedMember = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(TourMembershipGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tourId != widget.tourId) {
      _membership?.cancel();
      _confirmedMember = false;
      _listen();
    }
  }

  void _listen() {
    _membership = _repository.watchIsMember(widget.tourId).listen(
      (isMember) {
        if (isMember) {
          _confirmedMember = true;
        } else if (_confirmedMember) {
          _removed();
        }
      },
      // Not signed in, or Firebase is not set up: there is nothing to enforce.
      onError: (Object _) {},
    );
  }

  void _removed() {
    _membership?.cancel();
    _membership = null;
    unawaited(_repository.clearLocalTourData(widget.tourId));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final notice = context.l10n.translate('tour_membership_ended');
    context.go('/group-hub');
    // The hub's Scaffold is built with the next frame, and a snackbar needs one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(notice),
          backgroundColor: AppColors.midGreen,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  @override
  void dispose() {
    _membership?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
