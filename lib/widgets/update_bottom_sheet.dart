import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/services/update_downloader.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_client;
import 'package:url_launcher/url_launcher.dart';

class AppUpdateBottomSheet extends ConsumerWidget {
  final AppUpdateInfo update;
  final bool isRu;

  const AppUpdateBottomSheet({
    super.key,
    required this.update,
    required this.isRu,
  });

  static Future<void> show(BuildContext context, WidgetRef ref, AppUpdateInfo update, bool isRu) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppUpdateBottomSheet(update: update, isRu: isRu),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAmoled = ref.watch(amoledModeProvider);

    String archInfo = '';
    try {
      archInfo = rust_client.getAppArchitecture();
    } catch (_) {
      archInfo = Platform.version;
    }

    final appVersionAsync = ref.watch(appVersionProvider);
    final currentVerStr = appVersionAsync.value ?? UpdateChecker.currentVersion;
    final bestAsset = update.getBestAsset(archInfo);
    final targetLabel = update.targetArchitectureLabel;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isAmoled ? const Color(0xFF0A0A0A) : const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF8A897C).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4.5,
                decoration: BoxDecoration(
                  color: const Color(0xFF8A897C).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Header Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8A897C).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF8A897C).withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Color(0xFFD2D7DF),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRu ? 'Доступно обновление' : 'Update Available',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'v$currentVerStr',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFBDBBB0),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.arrow_forward_rounded, size: 12, color: Color(0xFF8A897C)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8A897C),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                update.tagName.startsWith('v') ? update.tagName : 'v${update.tagName}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFFBDBBB0)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Target Architecture & File Info Pill
            if (bestAsset != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isAmoled ? const Color(0xFF141414) : const Color(0xFF282828),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF353535)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Platform.isAndroid ? Icons.android_rounded : Icons.desktop_windows_rounded,
                        size: 16,
                        color: const Color(0xFF8A897C),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$targetLabel • ${bestAsset.name}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFD2D7DF),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (bestAsset.formattedSize.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3E3E3E),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            bestAsset.formattedSize,
                            style: const TextStyle(fontSize: 11, color: Color(0xFFBDBBB0), fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Changelog Box
            if (update.changelog.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text(
                  isRu ? 'Список изменений:' : 'What\'s new:',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD2D7DF),
                  ),
                ),
              ),
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAmoled ? const Color(0xFF121212) : const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF323232)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      update.changelog.trim(),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFBDBBB0),
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Download & Install Action Panel
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: _buildActionPanel(context, ref, bestAsset),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPanel(BuildContext context, WidgetRef ref, ReleaseAsset? asset) {
    final downloadState = ref.watch(updateDownloadStateProvider);

    if (downloadState.status == UpdateDownloadStatus.downloading) {
      final percentStr = (downloadState.progress * 100).toStringAsFixed(0);
      final receivedMb = (downloadState.receivedBytes / (1024 * 1024)).toStringAsFixed(1);
      final totalMb = (downloadState.totalBytes / (1024 * 1024)).toStringAsFixed(1);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isRu ? 'Загрузка обновления...' : 'Downloading update...',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                '$percentStr%',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF8A897C)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: downloadState.progress > 0 ? downloadState.progress : null,
              backgroundColor: const Color(0xFF353535),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8A897C)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$receivedMb MB / $totalMb MB',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFFBDBBB0)),
              ),
              TextButton(
                onPressed: () {
                  AppUpdateDownloader.cancel();
                  ref.read(updateDownloadStateProvider.notifier).state = const UpdateDownloadState();
                },
                child: Text(
                  isRu ? 'Отмена' : 'Cancel',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (downloadState.status == UpdateDownloadStatus.completed && downloadState.downloadedFile != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade900.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade700.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isRu ? 'Файл обновления успешно загружен' : 'Update file downloaded successfully',
                    style: const TextStyle(fontSize: 12, color: Colors.greenAccent),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8A897C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () async {
              final ok = await AppUpdateDownloader.installOrOpen(downloadState.downloadedFile!);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isRu ? 'Не удалось запустить установщик' : 'Failed to launch installer')),
                );
              }
            },
            icon: const Icon(Icons.install_mobile_rounded, size: 20),
            label: Text(
              isRu ? 'Установить обновление' : 'Install Update',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
        ],
      );
    }

    if (downloadState.status == UpdateDownloadStatus.failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade700.withValues(alpha: 0.5)),
            ),
            child: Text(
              '${isRu ? "Ошибка загрузки:" : "Download failed:"} ${downloadState.error ?? ""}',
              style: const TextStyle(fontSize: 11.5, color: Colors.redAccent),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8A897C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () {
              if (asset != null) {
                AppUpdateDownloader.download(
                  asset: asset,
                  onStateChanged: (s) {
                    ref.read(updateDownloadStateProvider.notifier).state = s;
                  },
                );
              }
            },
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: Text(isRu ? 'Повторить загрузку' : 'Retry Download'),
          ),
        ],
      );
    }

    // Default Idle State
    final sizeLabel = asset != null && asset.formattedSize.isNotEmpty ? ' (${asset.formattedSize})' : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8A897C),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () {
            if (asset != null) {
              AppUpdateDownloader.download(
                asset: asset,
                onStateChanged: (s) {
                  ref.read(updateDownloadStateProvider.notifier).state = s;
                },
              );
            } else {
              // Fallback to browser
              launchUrl(Uri.parse(update.releaseUrl), mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text(
            isRu ? 'Скачать и установить$sizeLabel' : 'Download and Install$sizeLabel',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFBDBBB0),
                  side: const BorderSide(color: Color(0xFF383838)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final uri = Uri.parse(update.releaseUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: Text(isRu ? 'GitHub релиз' : 'GitHub Release', style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                isRu ? 'Позже' : 'Later',
                style: const TextStyle(color: Color(0xFFBDBBB0), fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
