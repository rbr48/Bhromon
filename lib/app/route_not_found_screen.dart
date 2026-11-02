import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/localization/app_localizations.dart';

/// Shown for a link to a page the app does not have. It is localized, and it
/// does not show the router's technical error text.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/group-hub'),
        ),
        title: Text(context.l10n.translate('route_not_found_title')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.translate('route_not_found_body'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/group-hub'),
                child: Text(context.l10n.translate('route_not_found_action')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
