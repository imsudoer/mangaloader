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
  String get filterInProgress => isRu ? 'В процессе' : 'In progress';
  String get filterStreaks => isRu ? 'Стрики' : 'Streaks';
  String get filterChapters => isRu ? 'Главы' : 'Chapters';
  String get filterLibrary => isRu ? 'Библиотека' : 'Library';
  String get filterDownloads => isRu ? 'Оффлайн' : 'Downloads';
  String get filterTitles => isRu ? 'Тайтлы' : 'Titles';
  String get filterSpecial => isRu ? 'Особые' : 'Special';
  String get filterSecrets => isRu ? 'Секреты' : 'Secrets';

  String get share => isRu ? 'Поделиться' : 'Share';

  String get levelLabel => isRu ? 'Уровень' : 'Level';
  String get collectionLabel => isRu ? 'Коллекция' : 'Collection';
  String get secretsLabel => isRu ? 'Секретов найдено' : 'Secrets found';
  String get nearestTitle => isRu ? 'Ближайшее достижение' : 'Closest achievement';
  String remaining(String value) => isRu ? 'осталось $value' : '$value to go';
  String progressOf(String current, String max) => '$current / $max';
  String get unlockedLabel => isRu ? 'Открыто' : 'Unlocked';
  String get lockedLabel => isRu ? 'Закрыто' : 'Locked';
  String get hintLabel => isRu ? 'Подсказка' : 'Hint';
  String get rotateHint =>
      isRu ? 'Потяните карточку, чтобы повернуть' : 'Drag the card to rotate it';
  String get tapToOpen => isRu ? 'Нажмите, чтобы открыть' : 'Tap to open';
  String get shareCard => isRu ? 'Поделиться карточкой' : 'Share card';
  String get exportFailed =>
      isRu ? 'Не удалось сохранить карточку' : 'Could not save the card';
  String get secretTitle => '???';

  String get materialPaper => isRu ? 'Бумага' : 'Paper';
  String get materialPlastic => isRu ? 'Пластик' : 'Plastic';
  String get materialMetal => isRu ? 'Металл' : 'Metal';
  String get materialHolo => isRu ? 'Голография' : 'Holographic';
  String get materialDiamond => isRu ? 'Алмаз' : 'Diamond';
}