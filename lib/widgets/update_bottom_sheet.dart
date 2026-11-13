import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/l10n/strings/update_strings.dart';
import 'package:mangaloader/providers/settings_provider.dart';
import 'package:mangaloader/services/update_checker.dart';
import 'package:mangaloader/services/update_downloader.dart';
import 'package:mangaloader/src/rust/api/mangalib_client.dart' as rust_client;
import 'package:mangaloader/widgets/changelog_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mangaloader/theme/app_tokens.dart';

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
    final s = UpdateStrings(isRu);

    String archInfo = '';
    try {
      archInfo = rust_client.getAppArchitecture();
    } catch (_) {
      archInfo = Platform.version;
    }

    final appVersionAsync = ref.watch(appVersionProvider);
    final currentVerStr = appVersionAsync.value ?? UpdateChecker.currentVersion;
    final bestAsset = update.getBestAsset(archInfo);
    final targetLabel = update.getTargetArchitectureLabel(archInfo);
    final tagLabel = update.tagName.startsWith('v') ? update.tagName : 'v${update.tagName}';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isAmoled ? const Color(0xFF0A0A0A) : AppTokens.surfaceBase,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: AppTokens.accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 24,
            offset: Offset(0, -6),
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
                margin: const EdgeInsets.only(top: 12, bottom: 10),
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppTokens.accent.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Header Section with Glass Effect
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTokens.accent.withValues(alpha: 0.3),
                          AppTokens.accent.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTokens.accent.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: AppTokens.textPrimary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.updateAvailable,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTokens.surfaceRaised,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTokens.borderStrong),
                              ),
                              child: Text(
                                'v$currentVerStr',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTokens.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.arrow_forward_rounded, size: 13, color: AppTokens.accent),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTokens.accent, Color(0xFF6B6A5E)],
                                ),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                                ],
                              ),
                              child: Text(
                                tagLabel,
                                style: const TextStyle(
                                  fontSize: 11.5,
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
                    icon: const Icon(Icons.close_rounded, color: AppTokens.textSecondary),
                    tooltip: s.close,
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isAmoled ? const Color(0xFF141414) : const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF383838)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Platform.isAndroid ? Icons.android_rounded : Icons.desktop_windows_rounded,
                        size: 16,
                        color: AppTokens.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$targetLabel • ${bestAsset.name}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTokens.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (bestAsset.formattedSize.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF383838),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            bestAsset.formattedSize,
                            style: const TextStyle(fontSize: 11, color: AppTokens.textPrimary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Changelog Box with Polished Layout
            if (update.changelog.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 16, color: AppTokens.accent),
                    const SizedBox(width: 6),
                    Text(
                      s.whatsNew,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isAmoled ? const Color(0xFF111111) : AppTokens.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTokens.border),
                  ),
                  child: SingleChildScrollView(
                    child: ChangelogMarkdown(update.changelog.trim()),
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
    final s = UpdateStrings(isRu);

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
                s.downloading,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTokens.accent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$percentStr%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTokens.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: downloadState.progress > 0 ? downloadState.progress : null,
              backgroundColor: AppTokens.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.accent),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$receivedMb MB / $totalMb MB',
                style: const TextStyle(fontSize: 11.5, color: AppTokens.textSecondary),
              ),
              TextButton(
                onPressed: () {
                  AppUpdateDownloader.cancel();
                  ref.read(updateDownloadStateProvider.notifier).state = const UpdateDownloadState();
                },
                child: Text(
                  s.cancel,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade900.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.downloaded,
                    style: const TextStyle(fontSize: 12.5, color: Colors.greenAccent, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () async {
              final ok = await AppUpdateDownloader.installOrOpen(downloadState.downloadedFile!);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.installFailed)),
                );
              }
            },
            icon: const Icon(Icons.install_mobile_rounded, size: 20),
            label: Text(
              s.installUpdate,
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
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.downloadFailed(downloadState.error ?? ''),
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTokens.accent,
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
            label: Text(s.retryDownload),
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
            backgroundColor: AppTokens.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size.fromHeight(48),
            elevation: 2,
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
              launchUrl(Uri.parse(update.releaseUrl), mode: LaunchMode.externalApplication);
            }
          },
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text(
            s.downloadAndInstall(sizeLabel),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTokens.textPrimary,
                  side: const BorderSide(color: AppTokens.borderStrong),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () async {
                  final uri = Uri.parse(update.releaseUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                label: Text(s.githubRelease, style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                s.later,
                style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
