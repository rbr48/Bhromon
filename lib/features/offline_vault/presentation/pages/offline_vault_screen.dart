import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/entities/outbox_entry.dart';
import '../../../../core/theme/colors.dart';
import '../cubit/vault_cubit.dart';
import '../cubit/vault_state.dart';
import '../../../../core/utils/logger.dart';

import 'package:local_auth/local_auth.dart';

class OfflineVaultScreen extends StatefulWidget {
  const OfflineVaultScreen({super.key});

  @override
  State<OfflineVaultScreen> createState() => _OfflineVaultScreenState();
}

class _OfflineVaultScreenState extends State<OfflineVaultScreen> {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isAuthenticated = false;
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
    });

    try {
      final bool canCheckBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheckBiometrics && !isDeviceSupported) {
        // Fallback if biometrics are not configured/supported on this device
        setState(() {
          _isAuthenticated = true;
          _isAuthenticating = false;
        });
        return;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'Authenticate to access your secure Offline Vault',
        options: const AuthenticationOptions(
          biometricOnly: false, // Allows PIN/pattern/passcode fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      setState(() {
        _isAuthenticated = didAuthenticate;
        _isAuthenticating = false;
      });
    } catch (e) {
      logError('Biometric auth error: $e');
      setState(() {
        _isAuthenticated = false;
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return PopScope(
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          context.go('/group-hub');
        },
        child: Scaffold(
          backgroundColor: AppColors.backgroundDark,
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 80,
                    color: AppColors.mintGreen,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Offline Vault Locked',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Accessing your secure local vault containing cached maps, custom pins, and outbox logs requires authentication.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: AppColors.darkGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _authenticate,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text(
                      'Unlock Vault',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/group-hub');
                      }
                    },
                    child: const Text(
                      'Back to Tours',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/group-hub');
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/group-hub');
              }
            },
          ),
          title: const Text('Offline Vault'),
          backgroundColor: AppColors.cardDark,
          elevation: 0,
          centerTitle: true,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: BlocConsumer<VaultCubit, VaultState>(
              listener: (context, state) {
                if (state.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(state.errorMessage!),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              builder: (context, state) {
                // If still loading initial districts, show a spinner
                if (state.status == VaultStatus.loading &&
                    state.districts.isEmpty) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.mintGreen),
                  );
                }

                final districts = state.districts.isNotEmpty
                    ? state.districts
                    : _getDefaultDistricts();
                final downloaded = state.downloadedDistricts;
                final progressMap = state.downloadProgress;

                return RefreshIndicator(
                  onRefresh: () async {
                    context.read<VaultCubit>().refreshDistricts();
                  },
                  color: AppColors.mintGreen,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Outbox Sync Header Card
                        Card(
                          color: AppColors.cardDark,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Icon(
                                  state.isSyncing
                                      ? Icons.sync
                                      : Icons.cloud_done,
                                  color: state.isSyncing
                                      ? AppColors.gold
                                      : AppColors.mintGreen,
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        state.isSyncing
                                            ? 'Syncing Outbox...'
                                            : 'All changes synced',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16),
                                      ),
                                      Text(
                                        state.isSyncing
                                            ? 'Pushing offline edits to server...'
                                            : 'Local client is up to date',
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!state.isSyncing)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.mintGreen,
                                      foregroundColor: AppColors.darkGreen,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => context
                                        .read<VaultCubit>()
                                        .syncPendingData(),
                                    icon: const Icon(Icons.sync, size: 16),
                                    label: const Text('Sync Now'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (state.conflicts.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Card(
                            color: const Color(0xFF2C1E1A),
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(
                                  color: Colors.redAccent, width: 1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded,
                                          color: Colors.redAccent, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'SYNC CONFLICTS DETECTED',
                                        style: TextStyle(
                                            color: Colors.redAccent,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            letterSpacing: 1),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Some items could not be uploaded due to conflicting edits. Select a conflict below to resolve.',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(height: 12),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: state.conflicts.length,
                                    itemBuilder: (context, idx) {
                                      final entry = state.conflicts[idx];
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          '${entry.operation.toUpperCase()}: ${entry.collectionPath}/${entry.documentId}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          'Enqueued: ${DateTime.fromMillisecondsSinceEpoch(entry.enqueuedAt.millisecondsSinceEpoch).toLocal().toString().substring(0, 16)}',
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11),
                                        ),
                                        trailing: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.amber,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 4),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          onPressed: () =>
                                              _showRealConflictDialog(
                                                  context, entry),
                                          child: const Text('Resolve',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'OFFLINE DISTRICTS',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                // Sync all districts – download each not yet downloaded
                                for (final district in districts) {
                                  if (!downloaded.containsKey(district) &&
                                      !progressMap.containsKey(district)) {
                                    context
                                        .read<VaultCubit>()
                                        .downloadDistrict(district);
                                  }
                                }
                              },
                              icon: const Icon(Icons.sync,
                                  size: 16, color: AppColors.mintGreen),
                              label: const Text('Sync All',
                                  style: TextStyle(
                                      color: AppColors.mintGreen,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: districts.length,
                            itemBuilder: (context, index) {
                              final district = districts[index];
                              final isDownloaded =
                                  downloaded.containsKey(district);
                              final isDownloading =
                                  progressMap.containsKey(district);
                              final progress = progressMap[district] ?? 0.0;

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                color: Colors.black26,
                                child: ListTile(
                                  title: Text(district,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                  subtitle: isDownloading
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(
                                              value: progress,
                                              backgroundColor: Colors.white10,
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                          Color>(
                                                      AppColors.mintGreen),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                                '${(progress * 100).toInt()}% downloaded',
                                                style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11)),
                                          ],
                                        )
                                      : Text(
                                          isDownloaded
                                              ? 'Downloaded (${downloaded[district]} MB) • OSM Zoom 10-16'
                                              : 'Offline maps, pins, ProTips, and logs.',
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12),
                                        ),
                                  trailing: isDownloading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      AppColors.mintGreen)),
                                        )
                                      : isDownloaded
                                          ? IconButton(
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent),
                                              onPressed: () {
                                                context
                                                    .read<VaultCubit>()
                                                    .deleteDistrict(district);
                                              },
                                            )
                                          : ElevatedButton.icon(
                                              onPressed: () {
                                                context
                                                    .read<VaultCubit>()
                                                    .downloadDistrict(district);
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.midGreen,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                              ),
                                              icon: const Icon(
                                                  Icons
                                                      .download_for_offline_outlined,
                                                  size: 16),
                                              label: const Text('Get'),
                                            ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<String> _getDefaultDistricts() {
    return const [
      'Sylhet',
      'Rangamati',
      'Khulna',
      "Cox's Bazar",
      'Bandarban',
      'Dhaka',
      'Sajek',
    ];
  }

  void _showRealConflictDialog(BuildContext context, OutboxEntry entry) {
    final localJson = const JsonEncoder.withIndent('  ').convert(entry.payload);

    final serverPayload = entry.serverConflictPayload;
    final serverJson = serverPayload != null
        ? const JsonEncoder.withIndent('  ').convert(serverPayload)
        : 'Could not retrieve server version. Check connection or authorization.';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        insetPadding: const EdgeInsets.all(12),
        title: Row(
          children: [
            const Icon(Icons.difference_outlined, color: AppColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Resolve Conflict: ${entry.documentId}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(dialogContext).size.width * 0.9,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Operation: ${entry.operation.toUpperCase()} on ${entry.collectionPath}',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.midGreen.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'LOCAL (YOU)',
                              style: TextStyle(
                                  color: AppColors.midGreen,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 1),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  localJson,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'monospace',
                                      fontSize: 10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.midGreen,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                context
                                    .read<VaultCubit>()
                                    .resolveConflictKeepLocal(entry);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Re-queued local changes for syncing.')),
                                );
                              },
                              child: const Text('Keep Local',
                                  style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'SERVER / ERROR',
                              style: TextStyle(
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 1),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  serverJson,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontFamily: 'monospace',
                                      fontSize: 10),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                Navigator.pop(dialogContext);
                                context
                                    .read<VaultCubit>()
                                    .resolveConflictKeepServer(entry);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Local changes discarded. Keeping server version.')),
                                );
                              },
                              child: const Text('Keep Server',
                                  style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
            onPressed: () => Navigator.pop(dialogContext),
          ),
        ],
      ),
    );
  }
}
