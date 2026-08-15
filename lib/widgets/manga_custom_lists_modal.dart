import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangaloader/providers/custom_lists_provider.dart';
import 'package:mangaloader/src/rust/api/storage.dart' as rust_storage;

class MangaCustomListsModal extends ConsumerStatefulWidget {
  final int mangaId;
  final bool isRu;

  const MangaCustomListsModal({
    super.key,
    required this.mangaId,
    required this.isRu,
  });

  static Future<void> show(BuildContext context, int mangaId, bool isRu) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MangaCustomListsModal(mangaId: mangaId, isRu: isRu),
    );
  }

  @override
  ConsumerState<MangaCustomListsModal> createState() => _MangaCustomListsModalState();
}

class _MangaCustomListsModalState extends ConsumerState<MangaCustomListsModal> {
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _newListController = TextEditingController();

  Color _parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFF8A897C);
    }
  }

  void _showCreateListDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: Text(widget.isRu ? 'Новый список' : 'New List'),
        content: TextField(
          controller: _newListController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.isRu ? 'Название списка (напр. Шедевры)' : 'List name (e.g. Masterpieces)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.isRu ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF8A897C)),
            onPressed: () async {
              final name = _newListController.text.trim();
              if (name.isNotEmpty) {
                final created = await ref.read(customListsProvider.notifier).createList(name);
                if (created != null) {
                  await ref.read(customListsProvider.notifier).addMangaToList(created.id.toInt(), widget.mangaId);
                  ref.invalidate(mangaCustomListsProvider(widget.mangaId));
                }
                _newListController.clear();
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: Text(widget.isRu ? 'Создать' : 'Create'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    _newListController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customListsAsync = ref.watch(customListsProvider);
    final mangaListsAsync = ref.watch(mangaCustomListsProvider(widget.mangaId));
    final tagsAsync = ref.watch(mangaCustomTagsProvider(widget.mangaId));

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF353535), width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3E3E3E),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.isRu ? 'Пользовательские списки и теги' : 'Custom Lists & Tags',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, color: Color(0xFF8A897C)),
                    tooltip: widget.isRu ? 'Создать список' : 'New List',
                    onPressed: _showCreateListDialog,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Custom Lists Section
              Text(
                widget.isRu ? 'Персональные списки:' : 'Personal Lists:',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFBDBBB0)),
              ),
              const SizedBox(height: 6),

              customListsAsync.when(
                data: (lists) {
                  if (lists.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        widget.isRu ? 'Списков пока нет. Нажмите + чтобы создать!' : 'No custom lists yet. Tap + to create one!',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8A897C)),
                      ),
                    );
                  }

                  final assignedIds = mangaListsAsync.value ?? [];

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: lists.map((list) {
                      final listId = list.id.toInt();
                      final isSelected = assignedIds.contains(listId);
                      final col = _parseColor(list.color);

                      return FilterChip(
                        selected: isSelected,
                        label: Text(list.name),
                        avatar: Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.label_outline_rounded,
                          size: 16,
                          color: isSelected ? Colors.white : col,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : const Color(0xFFD2D7DF),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        selectedColor: col.withValues(alpha: 0.8),
                        backgroundColor: const Color(0xFF2A2A2A),
                        side: BorderSide(color: isSelected ? col : const Color(0xFF3A3A3A)),
                        onSelected: (val) async {
                          if (val) {
                            await ref.read(customListsProvider.notifier).addMangaToList(listId, widget.mangaId);
                          } else {
                            await ref.read(customListsProvider.notifier).removeMangaFromList(listId, widget.mangaId);
                          }
                          ref.invalidate(mangaCustomListsProvider(widget.mangaId));
                        },
                      );
                    }).toList(),
                  );
                },
                loading: () => const SizedBox(height: 32, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text('Ошибка: $e'),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),

              // Custom Tags Section
              Text(
                widget.isRu ? 'Персональные теги:' : 'Personal Tags:',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFFBDBBB0)),
              ),
              const SizedBox(height: 8),

              tagsAsync.when(
                data: (tags) {
                  return Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...tags.map((tag) {
                        return Chip(
                          label: Text(tag, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
                          backgroundColor: const Color(0xFF2C2C2C),
                          side: const BorderSide(color: Color(0xFF3E3E3E)),
                          deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF8A897C)),
                          onDeleted: () async {
                            await rust_storage.removeCustomTag(mangaId: widget.mangaId, tagName: tag);
                            ref.invalidate(mangaCustomTagsProvider(widget.mangaId));
                          },
                        );
                      }),
                      SizedBox(
                        width: 140,
                        height: 32,
                        child: TextField(
                          controller: _tagController,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: widget.isRu ? '+ Добавить тег' : '+ Add tag',
                            hintStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF8A897C)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF3E3E3E))),
                          ),
                          onSubmitted: (val) async {
                            final clean = val.trim();
                            if (clean.isNotEmpty) {
                              await rust_storage.addCustomTag(mangaId: widget.mangaId, tagName: clean);
                              _tagController.clear();
                              ref.invalidate(mangaCustomTagsProvider(widget.mangaId));
                            }
                          },
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const SizedBox(),
                error: (_, __) => const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
