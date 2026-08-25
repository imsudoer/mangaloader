import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/providers/library_provider.dart';
import 'package:mangaloader/providers/streak_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_api;
import 'package:mangaloader/src/rust/api/models.dart';
import 'package:mangaloader/widgets/manga_recap_modal.dart';
import 'package:mangaloader/widgets/user_search_modal.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  UserDetailedProfile? _detailedProfile;
  bool _isSyncing = false;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadProfileDetails();
    _checkNotifications();
  }

  Future<void> _loadProfileDetails() async {
    final basicProfile = ref.read(currentUserProfileProvider);
    if (basicProfile == null) return;

    try {
      final detailed = await rust_api.getUserDetailedProfile(userId: basicProfile.id);
      if (mounted) {
        setState(() {
          _detailedProfile = detailed;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkNotifications() async {
    try {
      final notif = await rust_api.getNotificationCount();
      if (mounted) {
        setState(() {
          _unreadNotifications = notif.count.toInt();
        });
      }
    } catch (_) {}
  }

  Future<void> _syncMangaLibBookmarks(bool isRu) async {
    final profile = ref.read(currentUserProfileProvider);
    if (profile == null) return;

    setState(() => _isSyncing = true);
    try {
      int imported = 0;
      final statusMap = {
        1: 'reading',
        2: 'plan_to_read',
        3: 'dropped',
        4: 'completed',
        5: 'favorites',
        6: 'on_hold',
      };

      for (final entry in statusMap.entries) {
        final bookmarks = await rust_api.getUserBookmarks(userId: profile.id, status: entry.key);
        if (bookmarks.isNotEmpty) {
          final count = await rust_storage.bulkImportBookmarks(items: bookmarks, listType: entry.value);
          imported += count.toInt();
        }
      }

      ref.read(libraryProvider.notifier).loadAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isRu ? 'Синхронизировано $imported тайтлов из MangaLib' : 'Synced $imported titles from MangaLib'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final isRu = Localizations.localeOf(context).languageCode == 'ru';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isRu ? 'Ошибка синхронизации: $e' : 'Sync error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showEditProfileDialog(BuildContext context, bool isRu) {
    final profile = _detailedProfile;
    final basicProfile = ref.read(currentUserProfileProvider);
    if (basicProfile == null) return;

    final usernameCtrl = TextEditingController(text: profile?.username ?? basicProfile.username);
    final aboutCtrl = TextEditingController(text: profile?.about ?? '');
    int selectedGender = profile?.gender.toInt() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isRu ? 'Редактировать профиль' : 'Edit Profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: usernameCtrl,
                  decoration: InputDecoration(
                    labelText: isRu ? 'Никнейм' : 'Username',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    filled: true,
                    fillColor: const Color(0xFF2C2C2C),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(isRu ? 'Пол' : 'Gender', style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF))),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: const Color(0xFF8A897C),
                    selectedForegroundColor: Colors.white,
                  ),
                  segments: [
                    ButtonSegment(value: 0, label: Text(isRu ? 'Не указан' : 'None')),
                    ButtonSegment(value: 1, label: Text(isRu ? 'Мужской' : 'Male')),
                    ButtonSegment(value: 2, label: Text(isRu ? 'Женский' : 'Female')),
                  ],
                  selected: {selectedGender},
                  onSelectionChanged: (val) => setDialogState(() => selectedGender = val.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: aboutCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: isRu ? 'О себе' : 'Bio / About',
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: const Color(0xFF2C2C2C),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isRu ? 'Отмена' : 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8A897C)),
              onPressed: () async {
                final nav = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                nav.pop();
                try {
                  await rust_api.updateUserProfile(
                    userId: basicProfile.id,
                    username: usernameCtrl.text.trim(),
                    gender: selectedGender,
                    about: aboutCtrl.text.trim(),
                    avatar: null,
                    cover: null,
                  );
                  _loadProfileDetails();
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(isRu ? 'Профиль успешно обновлен' : 'Profile updated successfully')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(isRu ? 'Ошибка обновления профиля: $e' : 'Failed to update profile: $e')),
                    );
                  }
                }
              },
              child: Text(isRu ? 'Сохранить' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context, bool isRu) async {
    final basicProfile = ref.read(currentUserProfileProvider);
    if (basicProfile == null) return;

    UserPrivacySettings privacy;
    try {
      privacy = await rust_api.getUserPrivacy(userId: basicProfile.id);
    } catch (_) {
      privacy = UserPrivacySettings(
        profileVisibility: 0,
        statisticsVisibility: 3,
        statisticsSiteIds: Int64List.fromList([1]),
        previousUsernamesVisibility: 0,
      );
    }

    if (!context.mounted) return;

    int profileVis = privacy.profileVisibility.toInt();
    int statsVis = privacy.statisticsVisibility.toInt();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF222222),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isRu ? 'Настройки приватности' : 'Privacy Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isRu ? 'Видимость профиля' : 'Profile Visibility', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: profileVis,
                dropdownColor: const Color(0xFF2C2C2C),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF2C2C2C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: [
                  DropdownMenuItem(value: 0, child: Text(isRu ? 'Виден всем' : 'Public to everyone')),
                  DropdownMenuItem(value: 1, child: Text(isRu ? 'Только друзьям' : 'Friends only')),
                  DropdownMenuItem(value: 2, child: Text(isRu ? 'Скрытый профиль' : 'Hidden / Private')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => profileVis = val);
                },
              ),
              const SizedBox(height: 16),
              Text(isRu ? 'Видимость статистики' : 'Statistics Visibility', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: statsVis,
                dropdownColor: const Color(0xFF2C2C2C),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF2C2C2C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: [
                  DropdownMenuItem(value: 0, child: Text(isRu ? 'Скрыта' : 'Hidden')),
                  DropdownMenuItem(value: 1, child: Text(isRu ? 'Только друзьям' : 'Friends only')),
                  DropdownMenuItem(value: 3, child: Text(isRu ? 'Видна всем' : 'Public to all')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => statsVis = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(isRu ? 'Отмена' : 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8A897C)),
              onPressed: () async {
                final nav = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                nav.pop();
                try {
                  await rust_api.updateUserPrivacy(
                    userId: basicProfile.id,
                    profileVisibility: profileVis,
                    statisticsVisibility: statsVis,
                    previousUsernamesVisibility: 0,
                  );
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(isRu ? 'Настройки приватности обновлены' : 'Privacy settings updated')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(isRu ? 'Ошибка обновления приватности: $e' : 'Failed to update privacy: $e')),
                    );
                  }
                }
              },
              child: Text(isRu ? 'Сохранить' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedLocale = ref.watch(localeProvider);
    final isRu = (selectedLocale?.languageCode ?? Localizations.localeOf(context).languageCode) == 'ru';
    final basicProfile = ref.watch(currentUserProfileProvider);
    final streakAsync = ref.watch(streakProvider);
    final streakCount = streakAsync.value?.currentStreak ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(isRu ? 'Профиль' : 'Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search_rounded),
            tooltip: isRu ? 'Поиск пользователей' : 'Search Users',
            onPressed: () => UserSearchModal.show(context),
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: isRu ? 'Уведомления' : 'Notifications',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isRu ? 'Уведомлений: $_unreadNotifications' : 'Notifications: $_unreadNotifications'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '$_unreadNotifications',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: isRu ? 'Настройки' : 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadProfileDetails();
          await _checkNotifications();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. User Profile Header Card
            _buildUserHeaderCard(context, isRu, basicProfile, streakCount),
            const SizedBox(height: 18),

            // 2. Manga Recap Spotlight Card
            _buildRecapSpotlightCard(context, isRu),
            const SizedBox(height: 18),

            // 3. Quick Stats & Achievements Grid
            _buildQuickActionsGrid(context, isRu),
            const SizedBox(height: 18),

            // 4. Account Settings & MangaLib Actions
            if (basicProfile != null) ...[
              _buildSectionTitle(isRu ? 'Управление аккаунтом MangaLib' : 'MangaLib Account Management'),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFF353535)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_outlined, color: Color(0xFF8A897C)),
                      title: Text(isRu ? 'Редактировать профиль' : 'Edit Profile'),
                      subtitle: Text(
                        isRu ? 'Изменить никнейм, пол и описание' : 'Change username, gender & bio',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showEditProfileDialog(context, isRu),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF8A897C)),
                      title: Text(isRu ? 'Приватность профиля' : 'Privacy Settings'),
                      subtitle: Text(
                        isRu ? 'Настройка видимости профиля и статистики' : 'Configure visibility of profile & stats',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showPrivacyDialog(context, isRu),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: _isSyncing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8A897C)))
                          : const Icon(Icons.sync_rounded, color: Color(0xFF8A897C)),
                      title: Text(isRu ? 'Синхронизировать закладки' : 'Sync MangaLib Bookmarks'),
                      subtitle: Text(
                        isRu ? 'Импортировать все списки закладок в библиотеку' : 'Import all bookmark lists into library',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _isSyncing ? null : () => _syncMangaLibBookmarks(isRu),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeaderCard(BuildContext context, bool isRu, UserProfile? basicProfile, int streakCount) {
    if (basicProfile == null) {
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF353535)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFF383838),
                    child: Icon(Icons.person_outline_rounded, size: 36, color: Color(0xFF8A897C)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRu ? 'Гостевой режим' : 'Guest Mode',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isRu ? 'Войдите для синхронизации с MangaLib' : 'Sign in to sync with MangaLib',
                          style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8A897C),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => context.push('/login'),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(isRu ? 'Войти в аккаунт MangaLib' : 'Sign in to MangaLib'),
              ),
            ],
          ),
        ),
      );
    }

    final avatarUrl = _detailedProfile?.avatarUrl ?? basicProfile.avatarUrl;
    final username = _detailedProfile?.username ?? basicProfile.username;
    final bio = _detailedProfile?.about ?? '';
    final points = _detailedProfile?.points ?? 0;
    final roles = _detailedProfile?.roles ?? [];

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF353535)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF8A897C).withValues(alpha: 0.22),
                  const Color(0xFF222222),
                ],
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFF383838),
                  backgroundImage: avatarUrl.isNotEmpty ? CachedNetworkImageProvider(avatarUrl) : null,
                  child: avatarUrl.isEmpty
                      ? const Icon(Icons.person, size: 38, color: Color(0xFF8A897C))
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${basicProfile.id}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFF9800), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_fire_department_rounded, size: 14, color: Color(0xFFFF9800)),
                                const SizedBox(width: 4),
                                Text(
                                  '$streakCount ${isRu ? 'дней' : 'days'}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF9800)),
                                ),
                              ],
                            ),
                          ),
                          if (points > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF64B5F6).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF64B5F6), width: 0.8),
                              ),
                              child: Text(
                                '$points pts',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64B5F6)),
                              ),
                            ),
                          ...roles.map((r) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A897C).withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(r, style: const TextStyle(fontSize: 10, color: Colors.white)),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Text(
                bio,
                style: const TextStyle(fontSize: 13, color: Color(0xFFD2D7DF), height: 1.3),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => _showEditProfileDialog(context, isRu),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(isRu ? 'Редактировать' : 'Edit'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                  onPressed: () {
                    ref.read(cookiesProvider.notifier).setCookies('');
                    ref.read(currentUserProfileProvider.notifier).setProfile(null);
                    setState(() => _detailedProfile = null);
                  },
                  icon: const Icon(Icons.logout_rounded, size: 16),
                  label: Text(isRu ? 'Выйти' : 'Logout'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecapSpotlightCard(BuildContext context, bool isRu) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2E2D24),
            Color(0xFF1E1E1E),
          ],
        ),
        border: Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.4), width: 1),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF8A897C).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8A897C), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isRu ? 'Manga Recap / Итоги чтения' : 'Manga Recap Summary',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  isRu ? 'Годовая сводка, рекорды и экспорт карточки' : 'Annual summary, tops & card export',
                  style: const TextStyle(fontSize: 12, color: Color(0xFFD2D7DF)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8A897C),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => MangaRecapModal.show(context),
            child: Text(isRu ? 'Открыть' : 'View', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context, bool isRu) {
    return Row(
      children: [
        Expanded(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/history'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Column(
                  children: [
                    const Icon(Icons.history_rounded, color: Color(0xFF81C784), size: 26),
                    const SizedBox(height: 6),
                    Text(
                      isRu ? 'История' : 'History',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRu ? 'Прочитанное' : 'Recent reads',
                      style: const TextStyle(fontSize: 10, color: Color(0xFFD2D7DF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/achievements'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Column(
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700), size: 26),
                    const SizedBox(height: 6),
                    Text(
                      isRu ? 'Достижения' : 'Awards',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRu ? 'Награды' : 'Levels & XP',
                      style: const TextStyle(fontSize: 10, color: Color(0xFFD2D7DF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFF353535)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/statistics'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Column(
                  children: [
                    const Icon(Icons.bar_chart_rounded, color: Color(0xFF64B5F6), size: 26),
                    const SizedBox(height: 6),
                    Text(
                      isRu ? 'Статистика' : 'Statistics',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRu ? 'Аналитика' : 'Analytics',
                      style: const TextStyle(fontSize: 10, color: Color(0xFFD2D7DF)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF8A897C)),
      ),
    );
  }
}
