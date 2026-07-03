import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// ✍️ Guided writing prompts shown when the diary editor is empty.
/// Prompts are mapped to block types so the user naturally creates richer entries.
class DiaryPromptWidget extends StatelessWidget {
  final VoidCallback onAddText;
  final VoidCallback onAddPhoto;
  final VoidCallback onAddCost;
  final VoidCallback onAddRoute;
  final VoidCallback onAddSafety;
  final VoidCallback onAddVoice;

  const DiaryPromptWidget({
    super.key,
    required this.onAddText,
    required this.onAddPhoto,
    required this.onAddCost,
    required this.onAddRoute,
    required this.onAddSafety,
    required this.onAddVoice,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.mintGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✍️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(
                'আপনার গল্প শুরু করুন',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.mintGreen,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Start Your Story',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 20),
          _PromptButton(
            emoji: '📖',
            bangla: 'সেরা মুহূর্তটা কী ছিল?',
            english: 'What was the moment you\'ll never forget?',
            onTap: onAddText,
          ),
          _PromptButton(
            emoji: '📸',
            bangla: 'একটি ছবি যোগ করুন',
            english: 'Add a photo from your trip',
            onTap: onAddPhoto,
          ),
          _PromptButton(
            emoji: '🎙️',
            bangla: 'ভয়েস নোট রেকর্ড করুন',
            english: 'Record a voice memory',
            onTap: onAddVoice,
          ),
          _PromptButton(
            emoji: '💰',
            bangla: 'কত টাকা খরচ হলো?',
            english: 'How much did you spend in total?',
            onTap: onAddCost,
          ),
          _PromptButton(
            emoji: '🗺️',
            bangla: 'রুট ম্যাপ আঁকুন',
            english: 'Draw your route on the map',
            onTap: onAddRoute,
          ),
          _PromptButton(
            emoji: '🛡️',
            bangla: 'বন্ধুদের জন্য টিপস দিন',
            english: 'Share safety tips for fellow travellers',
            onTap: onAddSafety,
          ),
        ],
      ),
    );
  }
}

class _PromptButton extends StatelessWidget {
  final String emoji;
  final String bangla;
  final String english;
  final VoidCallback onTap;

  const _PromptButton({
    required this.emoji,
    required this.bangla,
    required this.english,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bangla,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    english,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.add_circle_outline, color: Colors.white30, size: 18),
          ],
        ),
      ),
    );
  }
}
