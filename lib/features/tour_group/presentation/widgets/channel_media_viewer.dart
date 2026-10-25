import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/theme/colors.dart';
import '../../domain/models/channel_models.dart';

/// Opens a photo full screen, pinch to zoom, or a video with its controls.
Future<void> showChannelMediaViewer(
  BuildContext context,
  ChannelAttachment attachment,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _ChannelMediaPage(attachment: attachment),
    ),
  );
}

class _ChannelMediaPage extends StatelessWidget {
  final ChannelAttachment attachment;

  const _ChannelMediaPage({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: attachment.isVideo
          ? _VideoPane(url: attachment.url)
          : InteractiveViewer(
              child: Center(
                child: Image.network(
                  attachment.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _LoadFailed(
                    text: context.l10n.translate('chan_media_load_failed'),
                  ),
                ),
              ),
            ),
    );
  }
}

class _VideoPane extends StatefulWidget {
  final String url;

  const _VideoPane({required this.url});

  @override
  State<_VideoPane> createState() => _VideoPaneState();
}

class _VideoPaneState extends State<_VideoPane> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return _LoadFailed(
        text: context.l10n.translate('chan_media_load_failed'),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.midGreen),
      );
    }
    return Center(
      child: GestureDetector(
        onTap: _togglePlay,
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              if (!controller.value.isPlaying)
                const Icon(Icons.play_circle_fill,
                    color: Colors.white70, size: 64),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  final String text;

  const _LoadFailed({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.white70)),
    );
  }
}
