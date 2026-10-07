import 'package:flutter/material.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/records/edit-record-page.dart';

import 'category-display-name.dart';
import 'category-ordering.dart';

class CategoriesGrid extends StatelessWidget {
  const CategoriesGrid(
    this.categories, {
    super.key,
    this.goToEditMovementPage,
    this.initialDate,
    this.onManageCategories,
  });

  final List<Category?> categories;
  final bool? goToEditMovementPage;
  final DateTime? initialDate;
  final Future<void> Function()? onManageCategories;

  Future<void> _selectCategory(BuildContext context, Category category) async {
    if (goToEditMovementPage == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditRecordPage(
            passedCategory: category,
            initialDate: initialDate,
          ),
        ),
      );
      return;
    }
    if (context.mounted) Navigator.pop(context, category);
  }

  Widget _categoryTile(BuildContext context, Category category) {
    final iconColor = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: .75);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _selectCategory(context, category),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F3F3),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: category.iconEmoji != null
                  ? Text(
                      category.iconEmoji!,
                      style: const TextStyle(fontSize: 21),
                    )
                  : Icon(category.icon, size: 21, color: iconColor),
            ),
            const SizedBox(height: 5),
            Text(
              categoryDisplayName(category),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Category> items) {
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .55),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _categoryTile(context, items[index]),
              childCount: items.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: 82,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = categories.whereType<Category>().toList()
      ..sort(compareCategoriesSystemFirst);
    final system = visible.where((category) => category.isSystem).toList();
    final custom = visible.where((category) => !category.isSystem).toList();

    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无可用分类'),
            if (onManageCategories != null)
              TextButton.icon(
                onPressed: onManageCategories,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('管理分类'),
              ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (system.isNotEmpty) _section(context, '系统分类', system),
        if (custom.isNotEmpty) _section(context, '我的分类', custom),
        if (onManageCategories != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: TextButton.icon(
                onPressed: onManageCategories,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('管理分类'),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
