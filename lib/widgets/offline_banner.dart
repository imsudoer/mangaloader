import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/connectivity_provider.dart';

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    if (isOnline) return const SizedBox.shrink();

    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE65100).withValues(alpha: 0.92),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                isRu
                    ? 'Оффлайн-режим — доступны скачанные тайтлы и кэш'
                    : 'Offline Mode — downloaded manga and cache available',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
