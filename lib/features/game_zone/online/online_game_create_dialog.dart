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
  bool _isTournament = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: '${_selectedGame.label} Match');
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
        isTournament: _isTournament,
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
    final isBn = Localizations.maybeLocaleOf(context)?.languageCode == 'bn';
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
          Text(
            isBn ? 'অনলাইন গেম টেবিল তৈরি করুন' : 'Create Online Game Table',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isBn
                ? 'গ্রুপ সদস্যদের সাথে লাইভ ভয়েস লাউঞ্জসহ খেলুন।'
                : 'Host a match for group members with live voice lounge.',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Game selection chips
          Text(
            isBn ? 'গেম নির্বাচন করুন' : 'SELECT GAME',
            style: const TextStyle(
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
                    label: Text(type.localizedLabel(isBn)),
                    selected: isSelected,
                    selectedColor: AppColors.mintGreen,
                    backgroundColor: const Color(0xFF1E3526),
                    labelStyle: TextStyle(
                      color:
                          isSelected ? const Color(0xFF0F1E14) : Colors.white70,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected ? AppColors.mintGreen : Colors.white12,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedGame = type;
                          _nameController.text =
                              '${type.localizedLabel(isBn)} ${isBn ? "ম্যাচ" : "Match"}';
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
              labelText: isBn ? 'টেবিলের নাম' : 'Table Name',
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
            title: Text(
              isBn ? 'এআই বট দিয়ে আসন পূর্ণ করুন' : 'Auto-fill with AI Bots',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              isBn
                  ? 'খেলা শুরুর সময় খালি থাকা আসনগুলোতে স্বয়ংক্রিয়ভাবে বট যুক্ত হবে'
                  : 'Fill any empty seats with bots automatically on launch',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _autoFillBots,
            activeThumbColor: AppColors.mintGreen,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _autoFillBots = val),
          ),

          // Tour Tournament Match toggle
          SwitchListTile(
            title: Row(
              children: [
                const Icon(Icons.emoji_events_rounded,
                    color: AppColors.gold, size: 18),
                const SizedBox(width: 8),
                Text(
                  isBn ? 'ট্যুর টুর্নামেন্ট ম্যাচ' : 'Tour Tournament Match',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            subtitle: Text(
              isBn
                  ? 'গ্রুপ লিডারবোর্ডে পয়েন্ট যোগ হবে এবং টুর্নামেন্ট ট্রফি প্রদান করা হবে'
                  : 'Feature on Tour Leaderboard & award tournament trophies',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _isTournament,
            activeThumbColor: AppColors.gold,
            activeTrackColor: AppColors.gold.withValues(alpha: 0.3),
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _isTournament = val),
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
                : Text(
                    isBn
                        ? 'টেবিল তৈরি ও লবিতে প্রবেশ'
                        : 'Create Table & Enter Lobby',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}
