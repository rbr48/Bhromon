import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class GameZoneHubScreen extends StatelessWidget {
  const GameZoneHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14181B),
      appBar: AppBar(
        title: const Text('Travel GameZone',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E2429),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Hero Banner
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.35), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade400, Colors.amber.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.sports_esports,
                        color: Colors.black87, size: 36),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'In-Transit Offline Arcade',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Zero internet required. Perfect for long scenic drives, mountain buses, and quiet nights at camp.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'CHOOSE A GAME',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 14),

            // Card 29 (টুয়েন্টি নাইন)
            _buildGameCard(
              context,
              title: 'Card 29 (টুয়েন্টি নাইন)',
              subtitle:
                  'Classic South Asian 32-card trick-taking game. Bid, set trump, and team up with your AI partner.',
              icon: Icons.style,
              tag: 'CROWD FAVORITE',
              tagColor: Colors.redAccent,
              gradient: const [Color(0xFF1B5E20), Color(0xFF0D3311)],
              route: '/game-zone/card29',
            ),

            const SizedBox(height: 16),

            // Travel Chess AI
            _buildGameCard(
              context,
              title: 'Travel Chess AI',
              subtitle:
                  'Sharpen your mind on the road against our built-in Minimax chess engine across 3 difficulty levels.',
              icon: Icons.psychology,
              tag: 'STRATEGY',
              tagColor: Colors.blueAccent,
              gradient: const [Color(0xFF263238), Color(0xFF10171A)],
              route: '/game-zone/chess',
            ),

            const SizedBox(height: 16),

            // Ludo Express
            _buildGameCard(
              context,
              title: 'Ludo Express',
              subtitle:
                  'Roll the dice, race your 4 tokens to home base, and knock out your companions in classic 4-player Ludo.',
              icon: Icons.casino,
              tag: 'CASUAL & FUN',
              tagColor: Colors.amber,
              gradient: const [Color(0xFF5D4037), Color(0xFF271C19)],
              route: '/game-zone/ludo',
            ),

            const SizedBox(height: 16),

            // Teen Patti (তিন পাত্তি)
            _buildGameCard(
              context,
              title: 'Teen Patti (তিন পাত্তি)',
              subtitle:
                  'Classic South Asian 3-card poker. Play blind or seen, manage chips, and call showdowns with trail & pure sequence.',
              icon: Icons.filter_3,
              tag: 'DESI CLASSIC',
              tagColor: Colors.tealAccent,
              gradient: const [Color(0xFF004D40), Color(0xFF001F1A)],
              route: '/game-zone/teen-patti',
            ),

            const SizedBox(height: 16),

            // Carrom (ক্যারম)
            _buildGameCard(
              context,
              title: 'Carrom (ক্যারম)',
              subtitle:
                  'Flick the striker and sink your coins on a real-physics board. Cover the Queen, beat the bot or pass the phone.',
              icon: Icons.adjust,
              tag: 'FAMILY FAVORITE',
              tagColor: Colors.orangeAccent,
              gradient: const [Color(0xFF6D4C2E), Color(0xFF2B1A0E)],
              route: '/game-zone/carrom',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required String tag,
    required Color tagColor,
    required List<Color> gradient,
    required String route,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tagColor.withValues(alpha: 0.28), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: tagColor.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          const BoxShadow(
              color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(route),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        tagColor.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tagColor.withValues(alpha: 0.45)),
                    boxShadow: [
                      BoxShadow(
                        color: tagColor.withValues(alpha: 0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: tagColor, size: 34),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tagColor.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              tag,
                              style: TextStyle(
                                  color: tagColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_ios,
                    color: Colors.white54, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
