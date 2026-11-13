import 'package:flutter/widgets.dart';
import 'package:mangaloader/l10n/app_strings.dart';

class AchievementsStrings extends AppStrings {
  const AchievementsStrings(super.isRu);

  factory AchievementsStrings.of(BuildContext context) =>
      AchievementsStrings(AppStrings.isRussian(context));

  String get title => isRu ? 'Достижения' : 'Achievements';
  String shareText(String title, String description, String xp) => isRu
      ? 'Я получил достижение «$title» ($description) в MangaLoader! +$xp XP'
      : 'I unlocked the achievement "$title" ($description) in MangaLoader! +$xp XP';
  String xpProgress(String xp, String unlocked, String total) => isRu
      ? '$xp XP • $unlocked / $total открыто'
      : '$xp XP • $unlocked / $total unlocked';
  String nextLevel(String xp) =>
      isRu ? '$xp XP (След. уровень)' : '$xp XP (Next level)';

  String get filterAll => isRu ? 'Все' : 'All';
  String get filterUnlocked => isRu ? 'Полученные' : 'Unlocked';
  String get filterStreaks => isRu ? 'Стрики' : 'Streaks';
  String get filterChapters => isRu ? 'Главы' : 'Chapters';
  String get filterLibrary => isRu ? 'Библиотека' : 'Library';
  String get filterDownloads => isRu ? 'Оффлайн' : 'Downloads';
  String get filterSpecial => isRu ? 'Особые' : 'Special';

  String get share => isRu ? 'Поделиться' : 'Share';
}