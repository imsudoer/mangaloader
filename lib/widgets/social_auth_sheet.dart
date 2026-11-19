import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mangaloader/l10n/strings/comments_strings.dart';
import 'package:mangaloader/theme/app_tokens.dart';

enum SocialAction { vote, comment }

/// Sign-in prompt for votes and comments.
class SocialAuthSheet {
  static Future<void> show(BuildContext context, SocialAction action) async {
    final s = CommentsStrings.of(context);
    final title = action == SocialAction.vote ? s.signInToVote : s.signInToPost;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppTokens.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: AppTokens.borderStrong),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTokens.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTokens.accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTokens.accent.withValues(alpha: 0.35)),
                ),
                child: const Icon(
                  Icons.person_add_alt_1_rounded,
                  size: 26,
                  color: AppTokens.accent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.socialSignInBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.login_rounded, size: 18),
                label: Text(
                  s.signIn,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  s.later,
                  style: const TextStyle(fontSize: 13, color: AppTokens.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && context.mounted) {
      context.push('/login');
    }
  }
}