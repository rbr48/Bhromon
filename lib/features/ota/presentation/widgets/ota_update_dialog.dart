import 'dart:io';
import 'package:bhromon/core/theme/forest_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/theme/colors.dart';
import '../cubit/ota_cubit.dart';
import '../cubit/ota_state.dart';
import '../../../../core/theme/theme_context.dart';

class OtaUpdateDialog extends StatelessWidget {
  const OtaUpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OtaCubit, OtaState>(
      builder: (context, state) {
        if (state is OtaUpdateAvailable) {
          final info = state.info;
          return PopScope(
            // Prevent back-dismiss when mandatory or while downloading
            canPop: !info.isMandatory &&
                !state.isDownloading &&
                state.downloadProgress < 1.0,
            child: AlertDialog(
              backgroundColor: context.surfacePanel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                    color: AppColors.mintGreen.withValues(alpha: 0.2)),
              ),
              title: Row(
                children: [
                  Icon(Icons.system_update_outlined,
                      color: context.forest.accentText),
                  const SizedBox(width: 12),
                  Text(
                    'UPDATE AVAILABLE',
                    style: TextStyle(
                      color: context.forest.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A new version (${info.latestVersion}) of Bhromon is ready for you.',
                    style:
                        TextStyle(color: context.forest.text70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // ── Downloading state ──
                  if (state.isDownloading) ...[
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.mintGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Downloading update…',
                          style: TextStyle(
                            color: context.forest.accentText,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: state.downloadProgress > 0
                            ? state.downloadProgress
                            : null,
                        color: AppColors.mintGreen,
                        backgroundColor: context.forest.divider12,
                        minHeight: 7,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        state.downloadProgress > 0
                            ? '${(state.downloadProgress * 100).toInt()}%'
                            : 'Connecting…',
                        style: TextStyle(
                            color: context.forest.text54, fontSize: 12),
                      ),
                    ),

                    // ── Download complete — ready to install ──
                  ] else if (state.downloadProgress >= 1.0) ...[
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: context.forest.readable(Colors.greenAccent),
                            size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Download complete — ready to install',
                          style: TextStyle(
                            color: context.forest.readable(Colors.greenAccent),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    // ── Initial prompt ──
                  ] else ...[
                    Text(
                      'This update contains stability fixes, performance improvements, and updated content.',
                      style: TextStyle(
                          color: context.forest.text54,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ],
                ],
              ),
              actions: [
                // LATER — only visible on non-mandatory, non-downloading, pre-download
                if (!info.isMandatory &&
                    !state.isDownloading &&
                    state.downloadProgress < 1.0)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('LATER',
                        style: TextStyle(color: context.forest.text54)),
                  ),

                // UPDATE NOW — shown only when no download is in progress
                if (!state.isDownloading && state.downloadProgress < 1.0)
                  ElevatedButton(
                    onPressed: () => context.read<OtaCubit>().startDownload(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.mintGreen,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('UPDATE NOW'),
                  ),

                // INSTALL NOW — shown once download is complete
                if (!state.isDownloading && state.downloadProgress >= 1.0)
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        final tempDir = await getTemporaryDirectory();
                        final tempFile =
                            File('${tempDir.path}/bhromon-update.apk');
                        if (await tempFile.exists()) {
                          final result = await OpenFilex.open(
                            tempFile.path,
                            type: 'application/vnd.android.package-archive',
                          );
                          if (context.mounted) {
                            if (result.type == ResultType.done ||
                                result.type == ResultType.noAppToOpen) {
                              // Mark installed so this session doesn't re-prompt
                              context.read<OtaCubit>().markInstalled();
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Installer error: ${result.message}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'APK file not found — please download again.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Could not open installer: $e')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('INSTALL NOW'),
                  ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
