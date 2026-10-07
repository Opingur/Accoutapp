import 'package:flutter/material.dart';
import 'package:piggybank/categories/category-ordering.dart';
import 'package:piggybank/categories/category-display-name.dart';
import 'package:piggybank/categories/edit-category-page.dart';
import 'package:piggybank/models/category.dart';

import '../components/category_icon_circle.dart';

class CategoriesList extends StatelessWidget {
  const CategoriesList(this.categories, {super.key, this.callback});

  final List<Category?> categories;
  final Future<void> Function()? callback;

  Future<void> _openCategory(BuildContext context, Category category) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditCategoryPage(passedCategory: category),
      ),
    );
    await callback?.call();
  }

  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Category category) {
    return ListTile(
      dense: true,
      leading: CategoryIconCircle(
        iconEmoji: category.iconEmoji,
        iconDataFromDefaultIconSet: category.icon,
        backgroundColor: category.color,
        overlayIcon: category.isArchived ? Icons.archive : null,
      ),
      title: Text(
        categoryDisplayName(category),
        style: const TextStyle(fontSize: 16),
      ),
      subtitle: category.isSystem ? const Text('系统分类') : null,
      trailing: category.isSystem
          ? const Icon(Icons.lock_outline, size: 18)
          : null,
      onTap: () => _openCategory(context, category),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ordered = categories.whereType<Category>().toList()
      ..sort(compareCategoriesSystemFirst);
    final system = ordered.where((category) => category.isSystem).toList();
    final custom = ordered.where((category) => !category.isSystem).toList();

    if (ordered.isEmpty) {
      return const Center(child: Text('暂无分类'));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 92),
      children: [
        if (system.isNotEmpty) _heading(context, '系统分类'),
        ...system.map((category) => _tile(context, category)),
        if (custom.isNotEmpty) _heading(context, '我的分类'),
        ...custom.map((category) => _tile(context, category)),
      ],
    );
  }
}
