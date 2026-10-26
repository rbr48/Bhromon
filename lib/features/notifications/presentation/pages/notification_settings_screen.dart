import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/theme_context.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _syncAlerts = true;
  bool _trustUpgrades = true;
  bool _moderationAlerts = true;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/feed');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title: const Text(
            'SETTINGS & ACCOUNT',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Language / ভাষা',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                _buildLanguagePicker(),
                const SizedBox(height: 12),
                const Text(
                  'Theme / থিম',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                _buildThemePicker(),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),
                const Text(
                  'Push Notification Preferences',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 16),
                _buildToggle(
                  'Sync Conflicts',
                  'Get notified immediately when offline outbox conflicts occur.',
                  _syncAlerts,
                  (v) => setState(() => _syncAlerts = v),
                ),
                _buildToggle(
                  'Trust Upgrades',
                  'Get notified when your score upgrades your explorer status tier.',
                  _trustUpgrades,
                  (v) => setState(() => _trustUpgrades = v),
                ),
                _buildToggle(
                  'Moderation Alerts',
                  'Get notified when user reviews require content updates.',
                  _moderationAlerts,
                  (v) => setState(() => _moderationAlerts = v),
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),
                const Text(
                  'Account Security & Session',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surfacePanel,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline,
                            color: AppColors.mintGreen),
                        title: const Text('Change / Set Password',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        subtitle: const Text(
                            'Add or update password for email sign-in backup',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 11)),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.white54),
                        onTap: () => _showChangePasswordDialog(context),
                      ),
                      const Divider(color: Colors.white10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_forever,
                            color: Colors.redAccent),
                        title: const Text('Delete Profile & Account',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        subtitle: const Text(
                            'Permanently delete your profile and travel logs',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 11)),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.redAccent),
                        onTap: () => context.push('/delete-account'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: AppColors.mintGreen),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Bengali or English for the whole app. The choice is saved on this device.
  Widget _buildLanguagePicker() {
    return AnimatedBuilder(
      animation: LocaleController.instance,
      builder: (context, _) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.midGreen,
            selectedForegroundColor: Colors.white,
            foregroundColor: Colors.white70,
          ),
          segments: const [
            ButtonSegment(value: 'bn', label: Text('বাংলা')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {LocaleController.instance.locale.languageCode},
          onSelectionChanged: (selection) {
            unawaited(LocaleController.instance.setLanguage(selection.first));
          },
        ),
      ),
    );
  }

  Widget _buildThemePicker() {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<ThemeMode>(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.midGreen,
            selectedForegroundColor: Colors.white,
            foregroundColor: Colors.white70,
          ),
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: {ThemeController.instance.mode},
          onSelectionChanged: (selection) {
            unawaited(ThemeController.instance.setMode(selection.first));
          },
        ),
      ),
    );
  }

  Widget _buildToggle(
      String title, String subtitle, bool val, ValueChanged<bool> onChange) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        activeThumbColor: AppColors.mintGreen,
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        value: val,
        onChanged: onChange,
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surfacePanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.mintGreen.withValues(alpha: 0.2)),
        ),
        title: const Text(
          'SET NEW PASSWORD',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter a password to set on your account.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Minimum 6 characters',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                fillColor: Colors.white.withValues(alpha: 0.05),
                filled: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.mintGreen),
            onPressed: () async {
              final pwd = passwordController.text.trim();
              if (pwd.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Password must be at least 6 characters.')),
                );
                return;
              }

              Navigator.pop(dialogContext);
              setState(() => _isLoading = true);
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await user.updatePassword(pwd);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Password updated successfully!')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('No authenticated user session found.')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: ${e.toString()}')),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Update', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
