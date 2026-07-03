import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../../core/theme/theme_context.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
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
                  'Push Notification Preferences',
                  style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
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
                  style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surfacePanel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline, color: AppColors.mintGreen),
                        title: const Text('Change / Set Password', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Add or update password for email sign-in backup', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white30),
                        onTap: () => _showChangePasswordDialog(context),
                      ),
                      const Divider(color: Colors.white10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.logout, color: Colors.redAccent),
                        title: const Text('Log Out', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Sign out of your active explorer session', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white30),
                        onTap: () async {
                          context.read<AuthCubit>().signOut();
                        },
                      ),
                      const Divider(color: Colors.white10),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        title: const Text('Delete Profile & Account', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Permanently delete your profile and travel logs', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        trailing: const Icon(Icons.chevron_right, color: Colors.redAccent),
                        onTap: () => _showDeleteProfileConfirmation(context),
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

  Widget _buildToggle(String title, String subtitle, bool val, ValueChanged<bool> onChange) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        activeThumbColor: AppColors.mintGreen,
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                fillColor: Colors.white.withValues(alpha: 0.05),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.mintGreen),
            onPressed: () async {
              final pwd = passwordController.text.trim();
              if (pwd.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password must be at least 6 characters.')),
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
                      const SnackBar(content: Text('Password updated successfully!')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No authenticated user session found.')),
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

  void _showDeleteProfileConfirmation(BuildContext context) {
    final confirmationController = TextEditingController();
    bool canDelete = false;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: context.surfacePanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.redAccent, width: 0.8),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DELETE ACCOUNT',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'This action is irreversible. All your travel logs, profile information, and account details will be permanently deleted.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                'Type "DELETE" to confirm:',
                style: TextStyle(color: Colors.white30, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmationController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                ),
                onChanged: (val) {
                  setStateDialog(() {
                    canDelete = val.trim() == 'DELETE';
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canDelete ? Colors.redAccent : Colors.white10,
                foregroundColor: canDelete ? Colors.white : Colors.white24,
              ),
              onPressed: !canDelete
                  ? null
                  : () {
                      Navigator.pop(dialogContext);
                      _deleteProfileAndAccount();
                    },
              child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProfileAndAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final batch = FirebaseFirestore.instance.batch();
      
      // 1. Delete all travel logs
      final logsSnap = await FirebaseFirestore.instance
          .collection('trip_logs')
          .where('authorId', isEqualTo: user.uid)
          .get();
      for (final doc in logsSnap.docs) {
        batch.delete(doc.reference);
      }
      
      // 2. Delete explorer profile document
      batch.delete(
        FirebaseFirestore.instance.collection('explorer_profiles').doc(user.uid),
      );
      
      // 3. Delete Firebase Auth user
      await batch.commit();
      await user.delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted successfully.')),
        );
        context.read<AuthCubit>().signOut();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('requires-recent-login')
                  ? 'Sensitive operation. Please log out and sign back in to delete account.'
                  : 'Failed to delete account: $e',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
