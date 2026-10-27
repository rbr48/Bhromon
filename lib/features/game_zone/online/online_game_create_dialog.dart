import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/colors.dart';
import '../data/online_game_repository.dart';
import '../domain/models/online_game_session.dart';

class OnlineGameCreateDialog extends StatefulWidget {
  final String tourId;
  final OnlineGameRepository repository;

  const OnlineGameCreateDialog({
    super.key,
    required this.tourId,
    required this.repository,
  });

  static Future<void> show(
    BuildContext context, {
    required String tourId,
    required OnlineGameRepository repository,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OnlineGameCreateDialog(
        tourId: tourId,
        repository: repository,
      ),
    );
  }

  @override
  State<OnlineGameCreateDialog> createState() => _OnlineGameCreateDialogState();
}

class _OnlineGameCreateDialogState extends State<OnlineGameCreateDialog> {
  OnlineGameType _selectedGame = OnlineGameType.ludo;
  late final TextEditingController _nameController;
  bool _autoFillBots = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '${_selectedGame.label} Match');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    try {
      final gameId = await widget.repository.createGameSession(
        tourId: widget.tourId,
        gameType: _selectedGame,
        tableName: _nameController.text.trim(),
      );

      if (_autoFillBots) {
        await widget.repository.fillRemainingSeatsWithBots(
          tourId: widget.tourId,
          gameId: gameId,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        context.push('/game-zone/table/${widget.tourId}/$gameId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create table: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF13231A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Create Online Game Table',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Host a match for tour group members with live voice lounge.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Game selection chips
          const Text(
            'SELECT GAME',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: OnlineGameType.values.map((type) {
                final isSelected = type == _selectedGame;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(type.label),
                    selected: isSelected,
                    selectedColor: AppColors.mintGreen,
                    backgroundColor: const Color(0xFF1E3526),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF0F1E14) : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.mintGreen
                          : Colors.white12,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedGame = type;
                          _nameController.text = '${type.label} Match';
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Table name field
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Table Name',
              labelStyle: const TextStyle(color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF1A2F22),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.mintGreen),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Auto-fill bots toggle
          SwitchListTile(
            title: const Text(
              'Auto-fill with AI Bots',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: const Text(
              'Fill any empty seats with bots automatically on launch',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _autoFillBots,
            activeThumbColor: AppColors.mintGreen,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _autoFillBots = val),
          ),

          const SizedBox(height: 16),

          // Create button
          ElevatedButton(
            onPressed: _isCreating ? null : _handleCreate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.mintGreen,
              foregroundColor: const Color(0xFF0F1E14),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0F1E14),
                    ),
                  )
                : const Text(
                    'Create Table & Enter Lobby',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}
