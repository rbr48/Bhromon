import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/theme/theme_context.dart';

class SocialGraphWidget extends StatefulWidget {
  final String uid;

  const SocialGraphWidget({super.key, required this.uid});

  @override
  State<SocialGraphWidget> createState() => _SocialGraphWidgetState();
}

class _SocialGraphWidgetState extends State<SocialGraphWidget> {
  bool _isLoading = true;
  List<_GraphNode> _nodes = [];
  _GraphNode? _centerNode;

  @override
  void initState() {
    super.initState();
    _loadGraphData();
  }

  Future<void> _loadGraphData() async {
    try {
      // 1. Fetch current profile details for the center node
      final profileDoc = await FirebaseFirestore.instance
          .collection('explorer_profiles')
          .doc(widget.uid)
          .get();

      if (!profileDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final profileData = profileDoc.data()!;
      _centerNode = _GraphNode(
        uid: widget.uid,
        name: (profileData['displayName'] as String?) ?? 'Me',
        avatarUrl: profileData['avatarUrl'] as String?,
        isCenter: true,
      );

      // 2. Fetch follows data
      final followingQuery = await FirebaseFirestore.instance
          .collection('follows')
          .where('followerId', isEqualTo: widget.uid)
          .get();

      final followersQuery = await FirebaseFirestore.instance
          .collection('follows')
          .where('followedId', isEqualTo: widget.uid)
          .get();

      final followingIds = followingQuery.docs.map((doc) => doc['followedId'] as String).toSet();
      final followerIds = followersQuery.docs.map((doc) => doc['followerId'] as String).toSet();

      // Mutuals are the intersection of following and followers
      final mutualIds = followingIds.intersection(followerIds).toList();

      List<_GraphNode> orbitingNodes = [];

      if (mutualIds.isNotEmpty) {
        // Fetch up to 5 mutual profiles
        final limitIds = mutualIds.take(5).toList();
        final profilesQuery = await FirebaseFirestore.instance
            .collection('explorer_profiles')
            .where(FieldPath.documentId, whereIn: limitIds)
            .get();

        for (final doc in profilesQuery.docs) {
          final data = doc.data();
          orbitingNodes.add(_GraphNode(
            uid: doc.id,
            name: (data['displayName'] as String?) ?? 'Explorer',
            avatarUrl: data['avatarUrl'] as String?,
            isCenter: false,
          ));
        }
      }

      // 3. Fallback: If no mutual connections, fetch any popular/suggested profiles
      if (orbitingNodes.isEmpty) {
        final suggestionsQuery = await FirebaseFirestore.instance
            .collection('explorer_profiles')
            .limit(6)
            .get();

        for (final doc in suggestionsQuery.docs) {
          if (doc.id == widget.uid) continue; // Skip self
          final data = doc.data();
          orbitingNodes.add(_GraphNode(
            uid: doc.id,
            name: (data['displayName'] as String?) ?? 'Explorer',
            avatarUrl: data['avatarUrl'] as String?,
            isCenter: false,
            isSuggested: true,
          ));
          if (orbitingNodes.length >= 5) break;
        }
      }

      if (mounted) {
        setState(() {
          _nodes = orbitingNodes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading social graph: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 220,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: context.surfacePanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.mintGreen),
        ),
      );
    }

    if (_centerNode == null) {
      return const SizedBox.shrink();
    }

    final hasSuggested = _nodes.isNotEmpty && _nodes.any((n) => n.isSuggested);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfacePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.hub_outlined, color: AppColors.mintGreen, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    hasSuggested ? 'SUGGESTED EXPLORER NETWORK' : 'MUTUAL EXPLORER GRAPH',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              if (hasSuggested)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DISCOVER',
                    style: TextStyle(color: AppColors.gold, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const height = 200.0;
              final centerX = width / 2;
              const centerY = height / 2;

              // Compute node positions
              final List<Offset> positions = [];
              final numNodes = _nodes.length;
              const radius = 70.0;

              for (int i = 0; i < numNodes; i++) {
                final angle = (2 * pi / numNodes) * i - (pi / 2);
                final x = centerX + radius * cos(angle);
                final y = centerY + radius * sin(angle);
                positions.add(Offset(x, y));
              }

              return SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    // Connection lines background
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SocialConnectionPainter(
                          center: Offset(centerX, centerY),
                          nodes: positions,
                        ),
                      ),
                    ),
                    // Center node widget
                    Positioned(
                      left: centerX - 30,
                      top: centerY - 30,
                      child: _buildAvatarCircle(_centerNode!, 60),
                    ),
                    // Orbiting node widgets
                    ...List.generate(numNodes, (index) {
                      final pos = positions[index];
                      final node = _nodes[index];
                      return Positioned(
                        left: pos.dx - 22,
                        top: pos.dy - 22,
                        child: GestureDetector(
                          onTap: () => context.push('/profile/${node.uid}'),
                          child: Tooltip(
                            message: node.name,
                            child: _buildAvatarCircle(node, 44),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarCircle(_GraphNode node, double size) {
    final hasAvatar = node.avatarUrl != null && node.avatarUrl!.isNotEmpty;
    final themeColor = node.isCenter ? AppColors.mintGreen : (node.isSuggested ? AppColors.gold : Colors.cyanAccent);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: themeColor, width: node.isCenter ? 3 : 2),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: 0.3),
            blurRadius: node.isCenter ? 12 : 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size),
        child: hasAvatar
            ? CachedNetworkImage(
                imageUrl: node.avatarUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.black,
                  child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.mintGreen),
                ),
                errorWidget: (context, url, error) => _buildInitialsPlaceholder(node, size),
              )
            : _buildInitialsPlaceholder(node, size),
      ),
    );
  }

  Widget _buildInitialsPlaceholder(_GraphNode node, double size) {
    final initials = node.name.trim().isNotEmpty ? node.name.trim()[0].toUpperCase() : 'E';
    return Container(
      color: const Color(0xFF222222),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }
}

class _GraphNode {
  final String uid;
  final String name;
  final String? avatarUrl;
  final bool isCenter;
  final bool isSuggested;

  _GraphNode({
    required this.uid,
    required this.name,
    this.avatarUrl,
    this.isCenter = false,
    this.isSuggested = false,
  });
}

class _SocialConnectionPainter extends CustomPainter {
  final Offset center;
  final List<Offset> nodes;

  _SocialConnectionPainter({required this.center, required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mintGreen.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = AppColors.mintGreen.withValues(alpha: 0.08)
      ..strokeWidth = 5.0
      ..style = PaintingStyle.stroke;

    for (final node in nodes) {
      // Draw glow line
      canvas.drawLine(center, node, glowPaint);
      // Draw primary line
      canvas.drawLine(center, node, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
