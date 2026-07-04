import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 💬 Travel-specific entry reactions — warmer than generic likes.
/// Optimistic update: tapping increments count immediately.
class EntryReactionsWidget extends StatefulWidget {
  final Map<String, int> reactions;
  final String? myReaction;

  /// Called when a reaction is tapped with the reaction key.
  final void Function(String reactionKey)? onReact;

  const EntryReactionsWidget({
    super.key,
    required this.reactions,
    this.myReaction,
    this.onReact,
  });

  @override
  State<EntryReactionsWidget> createState() => _EntryReactionsWidgetState();
}

class _EntryReactionsWidgetState extends State<EntryReactionsWidget> {
  late Map<String, int> _counts;
  String? _myReaction;

  static const _reactionDefs = [
    {'key': 'wantToGo', 'emoji': '🗺️', 'label': 'যেতে চাই'},
    {'key': 'beenHere', 'emoji': '✅', 'label': 'গিয়েছি'},
    {'key': 'learned', 'emoji': '💡', 'label': 'শিখেছি'},
    {'key': 'beautiful', 'emoji': '🙏', 'label': 'সুন্দর'},
  ];

  @override
  void initState() {
    super.initState();
    _counts = Map.from(widget.reactions);
    _myReaction = widget.myReaction;
  }

  void _onTap(String key) {
    setState(() {
      if (_myReaction == key) {
        // Un-react
        _counts[key] = (_counts[key] ?? 1) - 1;
        _myReaction = null;
      } else {
        // Remove previous reaction
        if (_myReaction != null) {
          _counts[_myReaction!] = (_counts[_myReaction!] ?? 1) - 1;
        }
        // Add new reaction
        _counts[key] = (_counts[key] ?? 0) + 1;
        _myReaction = key;
      }
    });
    widget.onReact?.call(key);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _reactionDefs.map((r) {
        final key = r['key']!;
        final emoji = r['emoji']!;
        final count = _counts[key] ?? 0;
        final isSelected = _myReaction == key;

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => _onTap(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.mintGreen.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? AppColors.mintGreen : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        color:
                            isSelected ? AppColors.mintGreen : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
