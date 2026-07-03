import 'package:flutter/material.dart';
import '../value_objects/trip_mood.dart';
import '../theme/colors.dart';

/// 🏷️ Mood + Tag selector for diary entries.
/// Shows a mood picker row followed by travel tag chips in Bengali.
class TripTagsWidget extends StatefulWidget {
  final TripMood? selectedMood;
  final List<String> selectedTags;
  final ValueChanged<TripMood?> onMoodChanged;
  final ValueChanged<List<String>> onTagsChanged;

  const TripTagsWidget({
    super.key,
    this.selectedMood,
    this.selectedTags = const [],
    required this.onMoodChanged,
    required this.onTagsChanged,
  });

  @override
  State<TripTagsWidget> createState() => _TripTagsWidgetState();
}

class _TripTagsWidgetState extends State<TripTagsWidget> {
  late TripMood? _mood;
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _mood = widget.selectedMood;
    _tags = List.from(widget.selectedTags);
  }

  void _toggleMood(TripMood mood) {
    setState(() => _mood = _mood == mood ? null : mood);
    widget.onMoodChanged(_mood);
  }

  void _toggleTag(TripTag tag) {
    setState(() {
      final key = tag.name;
      if (_tags.contains(key)) {
        _tags.remove(key);
      } else {
        _tags.add(key);
      }
    });
    widget.onTagsChanged(List.from(_tags));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(text: 'ট্রিপের অনুভূতি', hint: 'How did it feel?'),
        const SizedBox(height: 10),
        // Mood row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: TripMood.values.map((mood) {
              final selected = _mood == mood;
              return _MoodChip(
                mood: mood,
                selected: selected,
                onTap: () => _toggleMood(mood),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        const _SectionLabel(text: 'ট্যাগ', hint: 'Add tags'),
        const SizedBox(height: 10),
        // Tags wrap
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TripTag.values.map((tag) {
            final selected = _tags.contains(tag.name);
            return _TagChip(
              tag: tag,
              selected: selected,
              onTap: () => _toggleTag(tag),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String hint;
  const _SectionLabel({required this.text, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          hint,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }
}

class _MoodChip extends StatelessWidget {
  final TripMood mood;
  final bool selected;
  final VoidCallback onTap;
  const _MoodChip({required this.mood, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.mintGreen.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? AppColors.mintGreen : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mood.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              mood.label,
              style: TextStyle(
                color: selected ? AppColors.mintGreen : Colors.white60,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final TripTag tag;
  final bool selected;
  final VoidCallback onTap;
  const _TagChip({required this.tag, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.gold.withValues(alpha: 0.6) : Colors.white10,
          ),
        ),
        child: Text(
          tag.label,
          style: TextStyle(
            color: selected ? AppColors.gold : Colors.white38,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
