import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mangaloader/theme/app_tokens.dart';
import 'package:mangaloader/services/achievement_events.dart';

/// Error state with an explanation, retry and an optional copy-log action.
class ErrorPlaceholder extends StatelessWidget {
  const ErrorPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.log,
    this.retryLabel = '',
    this.copyLabel = '',
    this.copiedLabel = '',
    this.onRetry,
    this.extraActions = const <Widget>[],
  });

  final IconData icon;
  final String title;
  final String message;
  final String? log;
  final String retryLabel;
  final String copyLabel;
  final String copiedLabel;
  final VoidCallback? onRetry;
  final List<Widget> extraActions;

  Future<void> _copyLog(BuildContext context) async {
    final text = log?.trim() ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    AchievementEvents.instance.increment('copied_logs');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copiedLabel),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLog = (log ?? '').trim().isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTokens.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTokens.accent.withValues(alpha: 0.30),
                  ),
                ),
                child: Icon(icon, size: 30, color: AppTokens.accent),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppTokens.textSecondary,
                ),
              ),
              if (hasLog && copyLabel.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTokens.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () => _copyLog(context),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: Text(copyLabel),
                ),
              ],
              if (onRetry != null || extraActions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    if (onRetry != null)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: Text(retryLabel),
                      ),
                    ...extraActions,
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}