import 'package:flutter/material.dart';

enum AchievementCategory { streak, chapters, library, downloads, special }
enum AchievementTier { bronze, silver, gold, platinum, legendary }

class Achievement {
  final String id;
  final AchievementCategory category;
  final String titleRu;
  final String titleEn;
  final String descRu;
  final String descEn;
  final IconData icon;
  final Color iconColor;
  final AchievementTier tier;
  final int xp;
  final int maxProgress;
  final int currentProgress;
  final bool isUnlocked;

  const Achievement({
    required this.id,
    required this.category,
    required this.titleRu,
    required this.titleEn,
    required this.descRu,
    required this.descEn,
    required this.icon,
    required this.iconColor,
    required this.tier,
    required this.xp,
    required this.maxProgress,
    required this.currentProgress,
    required this.isUnlocked,
  });

  double get progressRatio => maxProgress > 0 ? (currentProgress / maxProgress).clamp(0.0, 1.0) : (isUnlocked ? 1.0 : 0.0);

  String getTierName(bool isRu) {
    switch (tier) {
      case AchievementTier.bronze: return isRu ? 'Бронза' : 'Bronze';
      case AchievementTier.silver: return isRu ? 'Серебро' : 'Silver';
      case AchievementTier.gold: return isRu ? 'Золото' : 'Gold';
      case AchievementTier.platinum: return isRu ? 'Платина' : 'Platinum';
      case AchievementTier.legendary: return isRu ? 'Легендарное' : 'Legendary';
    }
  }

  Color getTierColor() {
    switch (tier) {
      case AchievementTier.bronze: return const Color(0xFFCD7F32);
      case AchievementTier.silver: return const Color(0xFFC0C0C0);
      case AchievementTier.gold: return const Color(0xFFFFD700);
      case AchievementTier.platinum: return const Color(0xFFE5E4E2);
      case AchievementTier.legendary: return const Color(0xFFFF3D00);
    }
  }
}
