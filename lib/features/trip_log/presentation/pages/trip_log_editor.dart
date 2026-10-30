import 'package:flutter/material.dart';
import '../../../../core/utils/concurrency.dart';
import '../../../../core/utils/image_sizing.dart';
import '../../../../core/utils/logger.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../../core/services/media_upload_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/colors.dart';
import '../bloc/trip_log_bloc.dart';
import '../bloc/trip_log_event.dart';
import '../bloc/trip_log_state.dart';
import '../../../../core/entities/trip_block.dart';
import '../../../../core/entities/trip_log.dart';
import '../../../../core/entities/cost_item.dart';
import '../widgets/trip_log_templates_sheet.dart';
import '../../../../core/value_objects/geo_coordinate.dart';
import '../../../feed/presentation/widgets/in_app_youtube_player.dart';
import '../../../../core/widgets/diary_quality_ring.dart';
import '../../../../core/widgets/weather_stamp_widget.dart';
import '../../../../core/widgets/diary_prompt_widget.dart';
import '../../../../core/widgets/voice_note_recorder_widget.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/value_objects/diary_visibility.dart';
import '../../../../core/localization/app_localizations.dart';

/// Photos uploaded in parallel when several are picked at once.
const int _kConcurrentUploads = 3;

class TripLogEditor extends StatefulWidget {
  final String pinId;
  final TripLog? existingTripLog;
  const TripLogEditor(
      {super.key, this.pinId = 'pin_sajek', this.existingTripLog});

  @override
  State<TripLogEditor> createState() => _TripLogEditorState();
}

class _TripLogEditorState extends State<TripLogEditor> {
  final TextEditingController _titleController = TextEditingController();
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = '';
  int _uploadTotalFiles = 0;
  int _uploadCurrentFileIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.existingTripLog != null) {
      context
          .read<TripLogBloc>()
          .add(LoadExistingTripLogEvent(widget.existingTripLog!));
    } else {
      context.read<TripLogBloc>().add(LoadDraftEvent(widget.pinId));
    }
    if (widget.existingTripLog == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final bloc = context.read<TripLogBloc>();
        if (bloc.state.blocks.isEmpty) {
          _showTemplatesSheet();
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TripLogBloc, TripLogState>(
      // Typing into the title or a block only changes text those fields
      // already hold; rebuilding the whole editor per keystroke is wasted.
      buildWhen: (previous, current) =>
          !TripLogState.onlyTypedTextChanged(previous, current),
      listener: (context, state) {
        if (state.status == EditorStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('TripLog published successfully! +50 Trust points.')),
          );
          context.pop();
        }
        if (state.status == EditorStatus.error && state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: AppColors.amber),
          );
        }
        // Sync title controller only once on draft load
        if (state.status == EditorStatus.idle &&
            _titleController.text.isEmpty &&
            state.title.isNotEmpty) {
          _titleController.text = state.title;
        }
      },
      builder: (context, state) {
        final isMobile = MediaQuery.of(context).size.width < 700;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.translate(widget.existingTripLog != null
                      ? 'editor_title_edit'
                      : 'editor_title_new'),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                Text(
                  widget.existingTripLog != null
                      ? 'Edit Diary'
                      : 'Write New Diary',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11),
                ),
              ],
            ),
            iconTheme: IconThemeData(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            actions: [
              // 🔒 Privacy toggle
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => _showPrivacySheet(context, state),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.visibility.icon,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Text(
                          state.visibility.label,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 🔵 Quality ring
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DiaryQualityRingWidget(
                  result: state.qualityResult,
                  size: 38,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.library_books_outlined,
                    color: AppColors.mintGreen),
                tooltip: 'টেমপ্লেট বেছে নিন',
                onPressed: _showTemplatesSheet,
              ),
              if (isMobile) ...[
                IconButton(
                  icon: Icon(
                    Icons.send_rounded,
                    color: (state.isComplete && !_isUploading)
                        ? AppColors.mintGreen
                        : Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.6),
                  ),
                  tooltip: context.l10n.translate('editor_publish'),
                  onPressed: _isUploading
                      ? null
                      : () {
                          if (state.isComplete) {
                            context.read<TripLogBloc>().add(
                                PublishTripLogEvent(_titleController.text));
                          } else {
                            _showCompletenessSheet(context, state);
                          }
                        },
                ),
                IconButton(
                  icon: Badge(
                    isLabelVisible: !state.isComplete,
                    child: const Icon(Icons.fact_check_outlined,
                        color: AppColors.mintGreen),
                  ),
                  tooltip: context.l10n.translate('req_checklist_title'),
                  onPressed: () => _showCompletenessSheet(context, state),
                ),
              ],
              if (state.status == EditorStatus.saving)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                              Theme.of(context).colorScheme.primary)),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                      child: Text(
                          Localizations.localeOf(context).languageCode == 'bn'
                              ? 'সংরক্ষিত'
                              : 'Saved',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12))),
                ),
            ],
          ),
          body: SafeArea(
            child: Row(
              children: [
                // Main Editor Panel
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isUploading) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: AppColors.mintGreen
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _uploadTotalFiles > 1
                                            ? '[$_uploadCurrentFileIndex/$_uploadTotalFiles] $_uploadStatus'
                                            : _uploadStatus,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${(_uploadProgress * 100).toInt()}%',
                                      style: const TextStyle(
                                          color: AppColors.mintGreen,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: _uploadProgress,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.3),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          AppColors.mintGreen),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Title Input
                        TextField(
                          controller: _titleController,
                          onChanged: (val) => context
                              .read<TripLogBloc>()
                              .add(UpdateTitleEvent(val)),
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5),
                          decoration: InputDecoration(
                            hintText: 'শিরোনাম দিন (যেমন: সুন্দরবনের গল্প)',
                            hintStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.6)),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                        // 🌦️ Weather stamp row
                        if (state.weatherSnapshot != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: WeatherStampWidget(
                                weather: state.weatherSnapshot!),
                          ),
                        Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.4),
                            height: 1),
                        const SizedBox(height: 12),

                        // Blocks list
                        Expanded(
                          child: state.blocks.isEmpty
                              ? SingleChildScrollView(
                                  child: DiaryPromptWidget(
                                    onAddText: () => _addTextBlock(context),
                                    onAddPhoto: () => _pickAndAddImage(),
                                    onAddCost: () {
                                      context.read<TripLogBloc>().add(
                                              AddBlockEvent(TripBlock.costEntry(
                                            id: 'cost_${DateTime.now().microsecondsSinceEpoch}',
                                            items: const [],
                                            currency: 'BDT',
                                          )));
                                    },
                                    onAddRoute: () {
                                      context
                                          .read<TripLogBloc>()
                                          .add(AddBlockEvent(TripBlock.route(
                                            id: 'route_${DateTime.now().microsecondsSinceEpoch}',
                                            points: const [],
                                            description: '',
                                          )));
                                    },
                                    onAddSafety: () {
                                      context.read<TripLogBloc>().add(
                                              AddBlockEvent(
                                                  TripBlock.safetyNote(
                                            id: 'safe_${DateTime.now().microsecondsSinceEpoch}',
                                            text: '',
                                            level: 'warning',
                                          )));
                                    },
                                    onAddVoice: () =>
                                        _showVoiceNoteDialog(context),
                                  ),
                                )
                              : ReorderableListView.builder(
                                  padding: const EdgeInsets.only(bottom: 80),
                                  onReorderItem: (oldIndex, newIndex) {
                                    // onReorderItem pre-adjusts newIndex for the removed item.
                                    final updated =
                                        List<TripBlock>.from(state.blocks);
                                    final item = updated.removeAt(oldIndex);
                                    updated.insert(newIndex, item);
                                    context
                                        .read<TripLogBloc>()
                                        .add(ReorderBlocksEvent(updated));
                                  },
                                  itemCount: state.blocks.length,
                                  itemBuilder: (context, index) {
                                    final block = state.blocks[index];
                                    return _buildBlockWrapper(
                                        context, index, block, state);
                                  },
                                ),
                        ),

                        // Floating Insertion Bar
                        Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 16),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.cardDark,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildAddBlockButton(
                                    Icons.text_fields_rounded, 'লেখা', () {
                                  context
                                      .read<TripLogBloc>()
                                      .add(AddBlockEvent(TripBlock.text(
                                        id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
                                        content: '',
                                      )));
                                }),
                                const SizedBox(width: 8),
                                _buildAddBlockButton(
                                    Icons.add_photo_alternate_rounded,
                                    'ছবি',
                                    _pickAndAddImage),
                                const SizedBox(width: 8),
                                _buildAddBlockButton(Icons.video_call_rounded,
                                    'ভিডিও', _showVideoSourceSelectorDialog),
                                const SizedBox(width: 8),
                                _buildAddBlockButton(Icons.mic_rounded, 'ভয়েস',
                                    () => _showVoiceNoteDialog(context)),
                                const SizedBox(width: 8),
                                _buildAddBlockButton(
                                    Icons.receipt_long_rounded, 'খরচ', () {
                                  context
                                      .read<TripLogBloc>()
                                      .add(AddBlockEvent(TripBlock.costEntry(
                                        id: 'cost_${DateTime.now().microsecondsSinceEpoch}',
                                        items: const [],
                                        currency: 'BDT',
                                      )));
                                }),
                                const SizedBox(width: 8),
                                _buildAddBlockButton(
                                    Icons.warning_amber_rounded, 'সেফটি', () {
                                  context
                                      .read<TripLogBloc>()
                                      .add(AddBlockEvent(TripBlock.safetyNote(
                                        id: 'safe_${DateTime.now().microsecondsSinceEpoch}',
                                        text: '',
                                        level: 'warning',
                                      )));
                                }),
                                const SizedBox(width: 8),
                                _buildAddBlockButton(
                                    Icons.alt_route_rounded, 'রুট', () {
                                  context
                                      .read<TripLogBloc>()
                                      .add(AddBlockEvent(TripBlock.route(
                                        id: 'route_${DateTime.now().microsecondsSinceEpoch}',
                                        points: const [],
                                        description: '',
                                      )));
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Right sidebar for desktop
                if (!isMobile)
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.cardDark,
                        border: Border(left: BorderSide(color: Colors.white12)),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.l10n.translate('req_checklist_title'),
                            style: const TextStyle(
                                color: Colors.white54,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 1.5),
                          ),
                          const SizedBox(height: 16),
                          // Privacy toggle
                          PrivacyToggleWidget(
                            current: state.visibility,
                            onChanged: (v) => context
                                .read<TripLogBloc>()
                                .add(UpdateVisibilityEvent(v)),
                          ),
                          const SizedBox(height: 20),
                          ..._buildChecklistItems(context, state),
                          const Spacer(),
                          ElevatedButton(
                            onPressed: (state.isComplete && !_isUploading)
                                ? () => context.read<TripLogBloc>().add(
                                    PublishTripLogEvent(_titleController.text))
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  (state.isComplete && !_isUploading)
                                      ? AppColors.midGreen
                                      : Colors.grey[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: Text(
                                '${context.l10n.translate('editor_publish')} ${state.visibility.icon}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Shows the privacy picker bottom sheet.
  void _showPrivacySheet(BuildContext context, TripLogState state) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'কে দেখতে পাবেন?',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            const Text(
              'Who can see your diary?',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            PrivacyToggleWidget(
              current: state.visibility,
              onChanged: (v) {
                context.read<TripLogBloc>().add(UpdateVisibilityEvent(v));
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 20),
            ...DiaryVisibility.values.map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Text(v.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          Text(v.labelEn,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Shows the voice note recorder as a bottom sheet.
  void _showVoiceNoteDialog(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.backgroundDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ভয়েস নোট যোগ করুন',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 20),
            VoiceNoteRecorderWidget(
              onRecordingComplete: (path, durationSeconds) {
                context.read<TripLogBloc>().add(AddBlockEvent(
                      TripBlock.voiceNote(
                        id: 'voice_${DateTime.now().microsecondsSinceEpoch}',
                        localPath: path,
                        durationSeconds: durationSeconds,
                      ),
                    ));
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildChecklistItems(BuildContext context, TripLogState state) {
    if (state.visibility == DiaryVisibility.private) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.mintGreen, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.translate('private_instant_posting_enabled'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      _buildChecklistItem(context.l10n.translate('req_title'),
          _titleController.text.isNotEmpty),
      _buildChecklistItem(context.l10n.translate('req_media'), state.hasImage),
      _buildChecklistItem(
          context.l10n.translate('req_safety'), state.hasSafetyNote),
      _buildChecklistItem(
          context.l10n.translate('req_cost'), state.hasCostEntry),
      _buildChecklistItem(context.l10n.translate('req_route'), state.hasRoute),
    ];
  }

  Widget _buildChecklistItem(String label, bool satisfied) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(
              satisfied
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: satisfied ? AppColors.mintGreen : Colors.white24,
              size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: satisfied ? Colors.white : Colors.white38,
                    fontWeight: satisfied ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddBlockButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.mintGreen, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockHeader(TripBlock block) {
    IconData icon = Icons.notes_rounded;
    String title = 'Text Block';
    Color color = Colors.white54;

    block.when(
      text: (_, __, ___) {
        icon = Icons.notes_rounded;
        title = 'Text Block';
        color = Colors.white54;
      },
      image: (_, __, ___, ____) {
        icon = Icons.image_outlined;
        title = 'Image Block';
        color = AppColors.mintGreen;
      },
      video: (_, __, ___, ____) {
        icon = Icons.videocam_outlined;
        title = 'Video Block';
        color = Colors.deepPurpleAccent;
      },
      costEntry: (_, __, ___) {
        icon = Icons.receipt_long_outlined;
        title = 'Expense List';
        color = AppColors.gold;
      },
      safetyNote: (_, __, level) {
        icon = Icons.warning_amber_rounded;
        title = 'Safety Note';
        if (level == 'danger') {
          color = Colors.redAccent;
        } else if (level == 'warning') {
          color = AppColors.amber;
        } else {
          color = Colors.blueAccent;
        }
      },
      route: (_, __, ___) {
        icon = Icons.alt_route_rounded;
        title = '🗺️ রুট ম্যাপ';
        color = Colors.tealAccent;
      },
      voiceNote: (_, __, ___, ____, _____) {
        icon = Icons.mic_rounded;
        title = '🎙️ ভয়েস নোট';
        color = Colors.orangeAccent;
      },
    );

    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildBlockWrapper(
      BuildContext context, int index, TripBlock block, TripLogState state) {
    Color indicatorColor = Colors.white24;
    block.when(
      text: (_, __, ___) => indicatorColor = Colors.white24,
      image: (_, __, ___, ____) => indicatorColor = AppColors.mintGreen,
      video: (_, __, ___, ____) => indicatorColor = Colors.deepPurpleAccent,
      costEntry: (_, __, ___) => indicatorColor = AppColors.gold,
      safetyNote: (_, __, level) {
        if (level == 'danger') {
          indicatorColor = Colors.redAccent;
        } else if (level == 'warning') {
          indicatorColor = AppColors.amber;
        } else {
          indicatorColor = Colors.blueAccent;
        }
      },
      route: (_, __, ___) => indicatorColor = Colors.tealAccent,
      voiceNote: (_, __, ___, ____, _____) =>
          indicatorColor = Colors.orangeAccent,
    );

    return Container(
      key: ValueKey(block.id),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                color: indicatorColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildBlockHeader(block),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_horiz_rounded,
                                color: Colors.white54, size: 18),
                            color: AppColors.cardDark,
                            elevation: 8,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 120),
                            onSelected: (value) {
                              if (value == 'move_up') {
                                final updated =
                                    List<TripBlock>.from(state.blocks);
                                final item = updated.removeAt(index);
                                updated.insert(index - 1, item);
                                context
                                    .read<TripLogBloc>()
                                    .add(ReorderBlocksEvent(updated));
                              } else if (value == 'move_down') {
                                final updated =
                                    List<TripBlock>.from(state.blocks);
                                final item = updated.removeAt(index);
                                updated.insert(index + 1, item);
                                context
                                    .read<TripLogBloc>()
                                    .add(ReorderBlocksEvent(updated));
                              } else if (value == 'delete') {
                                context
                                    .read<TripLogBloc>()
                                    .add(DeleteBlockEvent(index));
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'move_up',
                                enabled: index > 0,
                                child: const Row(
                                  children: [
                                    Icon(Icons.arrow_upward_rounded,
                                        color: Colors.white70, size: 16),
                                    SizedBox(width: 8),
                                    Text('Move Up',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'move_down',
                                enabled: index < state.blocks.length - 1,
                                child: const Row(
                                  children: [
                                    Icon(Icons.arrow_downward_rounded,
                                        color: Colors.white70, size: 16),
                                    SizedBox(width: 8),
                                    Text('Move Down',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuDivider(height: 1),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded,
                                        color: Colors.redAccent, size: 16),
                                    SizedBox(width: 8),
                                    Text('Delete',
                                        style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      block.when(
                        text: (id, content, isBold) => TextBlockEditor(
                          id: id,
                          initialContent: content,
                          onChanged: (newContent) =>
                              context.read<TripLogBloc>().add(
                                    UpdateBlockEvent(
                                        index,
                                        TripBlock.text(
                                            id: id, content: newContent)),
                                  ),
                        ),
                        image: (id, url, caption, localPath) =>
                            ImageBlockEditor(
                          id: id,
                          imageUrl: url,
                          localPath: localPath,
                          initialCaption: caption,
                          onCaptionChanged: (newCaption) =>
                              context.read<TripLogBloc>().add(
                                    UpdateBlockEvent(
                                        index,
                                        TripBlock.image(
                                            id: id,
                                            storageUrl: url,
                                            caption: newCaption,
                                            localPath: localPath)),
                                  ),
                        ),
                        video: (id, url, caption, localPath) =>
                            VideoBlockEditor(
                          id: id,
                          videoUrl: url,
                          localPath: localPath,
                          initialCaption: caption,
                          onCaptionChanged: (newCaption) =>
                              context.read<TripLogBloc>().add(
                                    UpdateBlockEvent(
                                        index,
                                        TripBlock.video(
                                            id: id,
                                            storageUrl: url,
                                            caption: newCaption,
                                            localPath: localPath)),
                                  ),
                        ),
                        costEntry: (id, items, currency) => CostBlockEditor(
                          id: id,
                          items: items,
                          currency: currency,
                          onUpdateItems: (newItems) =>
                              context.read<TripLogBloc>().add(
                                    UpdateBlockEvent(
                                        index,
                                        TripBlock.costEntry(
                                            id: id,
                                            items: newItems,
                                            currency: currency)),
                                  ),
                        ),
                        route: (id, points, description) => RouteBlockEditor(
                          id: id,
                          initialPoints: points,
                          initialDescription: description ?? '',
                          onChanged: (newPoints, newDescription) =>
                              context.read<TripLogBloc>().add(
                                    UpdateBlockEvent(
                                        index,
                                        TripBlock.route(
                                            id: id,
                                            points: newPoints,
                                            description: newDescription)),
                                  ),
                        ),
                        safetyNote: (id, text, level) => SafetyBlockEditor(
                          id: id,
                          initialText: text,
                          initialLevel: level,
                          onChanged: (newText, newLevel) =>
                              context.read<TripLogBloc>().add(
                                    UpdateBlockEvent(
                                        index,
                                        TripBlock.safetyNote(
                                            id: id,
                                            text: newText,
                                            level: newLevel)),
                                  ),
                        ),
                        voiceNote: (id, storageUrl, durationSeconds, localPath,
                                transcript) =>
                            _buildVoiceNoteDisplay(
                                id, durationSeconds, localPath, transcript),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders a voice note block for display/playback in the editor.
  Widget _buildVoiceNoteDisplay(
    String id,
    int durationSeconds,
    String? localPath,
    String? transcript,
  ) {
    final m = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (durationSeconds % 60).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.mic_rounded,
                  color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 10),
              Text(
                '$m:$s',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  localPath != null
                      ? '📱 স্থানীয়ভাবে সংরক্ষিত'
                      : '☁️ আপলোড হয়েছে',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        if (transcript != null && transcript.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '📝 $transcript',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  /// Adds a blank text block to the diary.
  void _addTextBlock(BuildContext context) {
    context.read<TripLogBloc>().add(AddBlockEvent(TripBlock.text(
          id: 'txt_${DateTime.now().microsecondsSinceEpoch}',
          content: '',
        )));
  }

  void _showTemplatesSheet() async {
    final template = await TripLogTemplatesSheet.show(context);
    if (template != null && mounted) {
      _applyTemplate(template);
    }
  }

  void _applyTemplate(TripTemplate template) {
    // Clear existing blocks first to avoid appending when changing templates
    context.read<TripLogBloc>().add(const ReorderBlocksEvent([]));

    // 1. Update title
    context
        .read<TripLogBloc>()
        .add(UpdateTitleEvent('${template.emoji} ${template.name}: My Trip'));
    _titleController.text = '${template.emoji} ${template.name}: My Trip';

    // 2. Add text blocks
    int idCounter = DateTime.now().millisecondsSinceEpoch;
    for (final section in template.suggestedSections) {
      final block = TripBlock.text(
        id: 'tmpl_txt_${idCounter++}',
        content: '### $section\n\nWrite about this section...',
        isBold: false,
      );
      context.read<TripLogBloc>().add(AddBlockEvent(block));
    }

    // 3. Add cost block
    if (template.defaultCosts.isNotEmpty) {
      final costItems = template.defaultCosts.entries.map((e) {
        return CostItem(
          label: e.key,
          amountBDT: (e.value as num).toInt(),
          category: 'other',
        );
      }).toList();
      final costBlock = TripBlock.costEntry(
        id: 'tmpl_cost_${idCounter++}',
        items: costItems,
        currency: 'BDT',
      );
      context.read<TripLogBloc>().add(AddBlockEvent(costBlock));
    }

    // 4. Add safety note
    if (template.sampleSafetyNote.isNotEmpty) {
      final safetyBlock = TripBlock.safetyNote(
        id: 'tmpl_safety_${idCounter++}',
        text: template.sampleSafetyNote,
        level: 'warning',
      );
      context.read<TripLogBloc>().add(AddBlockEvent(safetyBlock));
    }
  }

  void _showCompletenessSheet(BuildContext context, TripLogState state) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('PUBLISH CHECKLIST',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.5)),
                const SizedBox(height: 24),
                ..._buildChecklistItems(context, state),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: state.isComplete
                      ? () {
                          Navigator.pop(context);
                          context
                              .read<TripLogBloc>()
                              .add(PublishTripLogEvent(_titleController.text));
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.midGreen,
                    disabledBackgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Publish TripLog',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndAddImage() async {
    if (_isUploading) return;
    try {
      final ImagePicker picker = ImagePicker();
      // Cap the long edge: phone originals (12 MP+) are far bigger than any
      // screen shows, and every byte is uploaded and later decoded.
      final List<XFile> images = await picker.pickMultiImage(
        imageQuality: 80,
        maxWidth: kMaxCaptureDimension,
        maxHeight: kMaxCaptureDimension,
      );
      if (images.isEmpty) return;

      setState(() {
        _isUploading = true;
        _uploadTotalFiles = images.length;
        _uploadCurrentFileIndex = 0;
        _uploadProgress = 0.0;
        _uploadStatus = 'Starting upload of ${images.length} images...';
      });

      // Upload a few photos at a time instead of strictly one after another.
      final progress = List<double>.filled(images.length, 0);
      var finished = 0;
      void reportProgress() {
        if (!mounted) return;
        setState(() {
          _uploadCurrentFileIndex = finished;
          _uploadProgress =
              progress.fold<double>(0, (sum, p) => sum + p) / images.length;
          _uploadStatus =
              'Uploading ${images.length} photos ($finished done)...';
        });
      }

      final urls = await mapWithConcurrency<XFile, String>(
          images, _kConcurrentUploads, (image, i) async {
        String finalUrl = '';
        try {
          final String path =
              'trip_logs/${DateTime.now().millisecondsSinceEpoch}_${i}_${image.name}';
          void onProgress(double p) {
            progress[i] = p;
            reportProgress();
          }

          if (kIsWeb) {
            final bytes = await image.readAsBytes();
            finalUrl = await MediaUploadService.uploadBytes(
              bytes: bytes,
              path: path,
              contentType: 'image/jpeg',
              onProgress: onProgress,
            );
          } else {
            finalUrl = await MediaUploadService.uploadFile(
              file: File(image.path),
              path: path,
              onProgress: onProgress,
            );
          }
        } catch (e) {
          logError('Firebase Storage upload failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Upload failed for ${image.name}: $e'),
                  backgroundColor: AppColors.amber),
            );
          }
        }
        progress[i] = 1;
        finished++;
        reportProgress();
        return finalUrl;
      });

      // Add the blocks in the order the photos were picked.
      for (var i = 0; i < images.length; i++) {
        if (!mounted) break;
        if (urls[i].isEmpty) continue;
        context.read<TripLogBloc>().add(AddBlockEvent(TripBlock.image(
              id: 'img_${DateTime.now().microsecondsSinceEpoch}_$i',
              storageUrl: urls[i],
              caption: '',
              localPath: images[i].path,
            )));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully added ${images.length} photos')),
        );
      }
    } catch (e) {
      logError('Error picking images: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _pickAndAddVideo() async {
    if (_isUploading) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadStatus = 'Uploading video...';
    });
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      if (video != null) {
        String finalUrl = '';
        try {
          final String path =
              'trip_logs/videos/${DateTime.now().millisecondsSinceEpoch}_${video.name}';
          if (kIsWeb) {
            final bytes = await video.readAsBytes();
            finalUrl = await MediaUploadService.uploadBytes(
              bytes: bytes,
              path: path,
              contentType: 'video/mp4',
              onProgress: (progress) {
                if (mounted) {
                  setState(() {
                    _uploadProgress = progress;
                  });
                }
              },
            );
          } else {
            finalUrl = await MediaUploadService.uploadFile(
              file: File(video.path),
              path: path,
              onProgress: (progress) {
                if (mounted) {
                  setState(() {
                    _uploadProgress = progress;
                  });
                }
              },
            );
          }
        } catch (e) {
          logError('Firebase Storage video upload failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Video upload failed: $e'),
                  backgroundColor: AppColors.amber),
            );
          }
        }
        if (finalUrl.isNotEmpty && mounted) {
          context.read<TripLogBloc>().add(AddBlockEvent(TripBlock.video(
                id: 'vid_${DateTime.now().microsecondsSinceEpoch}',
                storageUrl: finalUrl,
                caption: '',
                localPath: video.path,
              )));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Video added')));
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Failed to upload video.'),
                  backgroundColor: AppColors.amber),
            );
          }
        }
      }
    } catch (e) {
      logError('Error picking video: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showVideoSourceSelectorDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Video',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library_rounded,
                  color: AppColors.mintGreen),
              title: const Text('Upload Local Video',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              subtitle: const Text('Select an authentic video from gallery',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _pickAndAddVideo();
              },
            ),
            const Divider(color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.link_rounded, color: Colors.white60),
              title: const Text('Paste External Video Link',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              subtitle: const Text('Optional YouTube video link',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                _showYouTubeLinkDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showYouTubeLinkDialog() {
    final TextEditingController urlController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Paste YouTube Link',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Supports standard video links, shorts, and embeds.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'https://www.youtube.com/watch?v=...',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.mintGreen,
              foregroundColor: const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                final videoId = extractYouTubeId(url);
                if (videoId != null && videoId.isNotEmpty) {
                  Navigator.pop(context);
                  context.read<TripLogBloc>().add(AddBlockEvent(TripBlock.video(
                        id: 'vid_${DateTime.now().microsecondsSinceEpoch}',
                        storageUrl: url,
                        caption: '',
                      )));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('YouTube video added')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Invalid YouTube URL. Please try again.'),
                        backgroundColor: AppColors.amber),
                  );
                }
              }
            },
            child: const Text('Add',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class TextBlockEditor extends StatefulWidget {
  final String id;
  final String initialContent;
  final void Function(String) onChanged;
  const TextBlockEditor(
      {super.key,
      required this.id,
      required this.initialContent,
      required this.onChanged});

  @override
  State<TextBlockEditor> createState() => _TextBlockEditorState();
}

class _TextBlockEditorState extends State<TextBlockEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  @override
  void didUpdateWidget(covariant TextBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialContent != widget.initialContent &&
        _controller.text != widget.initialContent) {
      _controller.text = widget.initialContent;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      style: TextStyle(color: cs.onSurface, fontSize: 15, height: 1.5),
      decoration: InputDecoration(
        hintText: 'Share details of your experience...',
        hintStyle: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 15),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      maxLines: null,
      onChanged: widget.onChanged,
    );
  }
}

class ImageBlockEditor extends StatefulWidget {
  final String id;
  final String imageUrl;
  final String? localPath;
  final String initialCaption;
  final void Function(String) onCaptionChanged;
  const ImageBlockEditor(
      {super.key,
      required this.id,
      required this.imageUrl,
      this.localPath,
      required this.initialCaption,
      required this.onCaptionChanged});

  @override
  State<ImageBlockEditor> createState() => _ImageBlockEditorState();
}

class _ImageBlockEditorState extends State<ImageBlockEditor> {
  late TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
  }

  @override
  void didUpdateWidget(covariant ImageBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCaption != widget.initialCaption &&
        _captionController.text != widget.initialCaption) {
      _captionController.text = widget.initialCaption;
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: (widget.localPath != null &&
                  widget.localPath!.isNotEmpty &&
                  !kIsWeb &&
                  File(widget.localPath!).existsSync())
              ? Image.file(
                  File(widget.localPath!),
                  cacheWidth: context.decodeWidth(),
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
              : CachedNetworkImage(
                  memCacheWidth: context.decodeWidth(),
                  imageUrl: widget.imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 200,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    child: const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.mintGreen),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 200,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    child: Icon(Icons.broken_image,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _captionController,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Add a caption to this photo...',
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
          ),
          onChanged: widget.onCaptionChanged,
        ),
      ],
    );
  }
}

class VideoBlockEditor extends StatefulWidget {
  final String id;
  final String videoUrl;
  final String? localPath;
  final String initialCaption;
  final void Function(String) onCaptionChanged;
  const VideoBlockEditor(
      {super.key,
      required this.id,
      required this.videoUrl,
      this.localPath,
      required this.initialCaption,
      required this.onCaptionChanged});

  @override
  State<VideoBlockEditor> createState() => _VideoBlockEditorState();
}

class _VideoBlockEditorState extends State<VideoBlockEditor> {
  late TextEditingController _captionController;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
  }

  @override
  void didUpdateWidget(covariant VideoBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCaption != widget.initialCaption &&
        _captionController.text != widget.initialCaption) {
      _captionController.text = widget.initialCaption;
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoId = extractYouTubeId(widget.videoUrl);
    final String? thumbnailUrl = videoId != null && videoId.isNotEmpty
        ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.3)),
                ),
                child: thumbnailUrl != null
                    ? CachedNetworkImage(
                        memCacheWidth: context.decodeWidth(),
                        imageUrl: thumbnailUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Icon(
                            Icons.video_collection_rounded,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            size: 48),
                      )
                    : Icon(Icons.video_collection_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 48),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: AppColors.mintGreen, size: 36),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _captionController,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Add a caption to this video...',
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
          ),
          onChanged: widget.onCaptionChanged,
        ),
      ],
    );
  }
}

class CostBlockEditor extends StatefulWidget {
  final String id;
  final List<CostItem> items;
  final String currency;
  final void Function(List<CostItem>) onUpdateItems;
  const CostBlockEditor(
      {super.key,
      required this.id,
      required this.items,
      required this.currency,
      required this.onUpdateItems});

  @override
  State<CostBlockEditor> createState() => _CostBlockEditorState();
}

class _CostBlockEditorState extends State<CostBlockEditor> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  int get total => widget.items.fold(0, (sum, item) => sum + item.amountBDT);

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.items.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                ...widget.items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      children: [
                        const Icon(Icons.label_outline_rounded,
                            color: AppColors.gold, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 14),
                          ),
                        ),
                        Text(
                          '${item.amountBDT} BDT',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded,
                              color: Colors.redAccent, size: 16),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            final updated = List<CostItem>.from(widget.items)
                              ..removeAt(idx);
                            widget.onUpdateItems(updated);
                          },
                        ),
                      ],
                    ),
                  );
                }),
                Divider(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.4),
                    height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Expenses:',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      Text(
                        '$total BDT',
                        style: const TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _nameController,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Expense item (e.g. Bus fare)',
                  hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Amount',
                  hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add_circle_rounded,
                  color: AppColors.mintGreen, size: 28),
              onPressed: () {
                final name = _nameController.text.trim();
                final amount = int.tryParse(_amountController.text.trim()) ?? 0;
                if (name.isNotEmpty && amount > 0) {
                  widget.onUpdateItems([
                    ...widget.items,
                    CostItem(
                        label: name, amountBDT: amount, category: 'general')
                  ]);
                  _nameController.clear();
                  _amountController.clear();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class SafetyBlockEditor extends StatefulWidget {
  final String id;
  final String initialText;
  final String initialLevel;
  final void Function(String, String) onChanged;
  const SafetyBlockEditor(
      {super.key,
      required this.id,
      required this.initialText,
      required this.initialLevel,
      required this.onChanged});

  @override
  State<SafetyBlockEditor> createState() => _SafetyBlockEditorState();
}

class _SafetyBlockEditorState extends State<SafetyBlockEditor> {
  late TextEditingController _textController;
  late String _selectedLevel;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _selectedLevel = widget.initialLevel;
  }

  @override
  void didUpdateWidget(covariant SafetyBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialText != widget.initialText &&
        _textController.text != widget.initialText) {
      _textController.text = widget.initialText;
    }
    if (oldWidget.initialLevel != widget.initialLevel) {
      _selectedLevel = widget.initialLevel;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color cardColor;
    Color accentColor;

    if (_selectedLevel == 'danger') {
      cardColor = Colors.redAccent.withValues(alpha: 0.05);
      accentColor = Colors.redAccent;
    } else if (_selectedLevel == 'warning') {
      cardColor = AppColors.amber.withValues(alpha: 0.05);
      accentColor = AppColors.amber;
    } else {
      cardColor = Colors.blueAccent.withValues(alpha: 0.05);
      accentColor = Colors.blueAccent;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ALERT LEVEL',
                style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    letterSpacing: 1.0),
              ),
              Wrap(
                spacing: 6,
                children: ['info', 'warning', 'danger'].map((level) {
                  final isSelected = _selectedLevel == level;
                  Color levelColor;
                  if (level == 'danger') {
                    levelColor = Colors.redAccent;
                  } else if (level == 'warning') {
                    levelColor = AppColors.amber;
                  } else {
                    levelColor = Colors.blueAccent;
                  }
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedLevel = level);
                      widget.onChanged(_textController.text, level);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? levelColor
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        level.toUpperCase(),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.black
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textController,
            maxLines: null,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
            decoration: InputDecoration(
              hintText:
                  'Describe safety warnings (e.g. steep slopes, heavy tides)',
              hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 14),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (val) => widget.onChanged(val, _selectedLevel),
          ),
        ],
      ),
    );
  }
}

class RouteBlockEditor extends StatefulWidget {
  final String id;
  final List<GeoCoordinate> initialPoints;
  final String initialDescription;
  final void Function(List<GeoCoordinate>, String) onChanged;
  const RouteBlockEditor(
      {super.key,
      required this.id,
      required this.initialPoints,
      required this.initialDescription,
      required this.onChanged});

  @override
  State<RouteBlockEditor> createState() => _RouteBlockEditorState();
}

class _RouteBlockEditorState extends State<RouteBlockEditor> {
  late TextEditingController _descController;
  final List<TextEditingController> _pointControllers = [];

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.initialDescription);
    _syncPointControllers();
  }

  void _syncPointControllers() {
    for (var c in _pointControllers) {
      c.dispose();
    }
    _pointControllers.clear();
    for (var point in widget.initialPoints) {
      _pointControllers.add(
          TextEditingController(text: "${point.latitude}, ${point.longitude}"));
    }
  }

  @override
  void didUpdateWidget(covariant RouteBlockEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDescription != widget.initialDescription &&
        _descController.text != widget.initialDescription) {
      _descController.text = widget.initialDescription;
    }
    if (oldWidget.initialPoints.length != widget.initialPoints.length ||
        !_listsEqual(oldWidget.initialPoints, widget.initialPoints)) {
      _syncPointControllers();
    }
  }

  bool _listsEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].toString() != b[i].toString()) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _descController.dispose();
    for (var c in _pointControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _notifyParent() {
    final List<GeoCoordinate> points = [];
    for (var c in _pointControllers) {
      final text = c.text.trim();
      if (text.isEmpty) continue;
      final parts = text.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          points.add(GeoCoordinate(latitude: lat, longitude: lng));
          continue;
        }
      }
      points.add(const GeoCoordinate(latitude: 23.6850, longitude: 90.3563));
    }
    widget.onChanged(points, _descController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pointControllers.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _pointControllers.length,
            itemBuilder: (context, idx) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: Colors.tealAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _pointControllers[idx],
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Latitude, Longitude (e.g. 23.68, 90.35)',
                          hintStyle: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 13),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (_) => _notifyParent(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          color: Colors.redAccent, size: 18),
                      onPressed: () {
                        _pointControllers[idx].dispose();
                        _pointControllers.removeAt(idx);
                        _notifyParent();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              _pointControllers.add(TextEditingController());
              setState(() {});
            },
            icon: const Icon(Icons.add_location_alt_rounded,
                color: Colors.tealAccent, size: 16),
            label: const Text('Add waypoint coordinate',
                style: TextStyle(color: Colors.tealAccent, fontSize: 13)),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descController,
          maxLines: 2,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          decoration: InputDecoration(
            hintText:
                'Describe the route path (e.g. "Take the hiking path towards the waterfall")',
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (_) => _notifyParent(),
        ),
      ],
    );
  }
}
