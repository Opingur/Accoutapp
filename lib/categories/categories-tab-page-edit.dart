import 'package:flutter/material.dart';
import 'package:piggybank/categories/categories-list.dart';
import 'package:piggybank/categories/category-ordering.dart';
import 'package:piggybank/categories/edit-category-page.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/services/database/database-interface.dart';
import 'package:piggybank/services/service-config.dart';

class TabCategories extends StatefulWidget {
  const TabCategories({super.key});

  @override
  TabCategoriesState createState() => TabCategoriesState();
}

class TabCategoriesState extends State<TabCategories>
    with SingleTickerProviderStateMixin {
  List<Category?>? _categories;
  late final TabController _tabController;
  final DatabaseInterface database = ServiceConfig.database;
  bool showArchived = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
    _fetchCategories();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    final categories = await database.getAllCategories();
    sortCategoriesSystemFirst(categories);
    if (mounted) setState(() => _categories = categories);
  }

  Future<void> _addCategory(CategoryType type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditCategoryPage(categoryType: type)),
    );
    await _fetchCategories();
  }

  List<Category?> _categoriesFor(CategoryType type) {
    return (_categories ?? [])
        .where(
          (category) =>
              category!.categoryType == type &&
              category.isArchived == showArchived,
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark
        ? colorScheme.surfaceContainer
        : const Color(0xFFFFD400);
    final headerForeground = isDark
        ? colorScheme.onSurface
        : const Color(0xFF252525);
    final headerMuted = isDark
        ? colorScheme.onSurface.withValues(alpha: .6)
        : const Color(0xFF5F5424);
    final selectedType = _tabController.index == 0
        ? CategoryType.expense
        : CategoryType.income;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: headerColor,
        foregroundColor: headerForeground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(showArchived ? '已归档分类' : '分类管理'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: headerForeground,
          indicatorWeight: 3,
          labelColor: headerForeground,
          unselectedLabelColor: headerMuted,
          tabs: const [
            Tab(text: '支出'),
            Tab(text: '收入'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: showArchived ? '显示可用分类' : '显示已归档分类',
            icon: Icon(
              showArchived ? Icons.visibility_outlined : Icons.archive_outlined,
            ),
            onPressed: () => setState(() => showArchived = !showArchived),
          ),
        ],
      ),
      body: _categories == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                CategoriesList(
                  _categoriesFor(CategoryType.expense),
                  callback: _fetchCategories,
                ),
                CategoriesList(
                  _categoriesFor(CategoryType.income),
                  callback: _fetchCategories,
                ),
              ],
            ),
      floatingActionButton: showArchived
          ? null
          : FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: isDark
                  ? colorScheme.primary
                  : const Color(0xFFFFD400),
              foregroundColor: const Color(0xFF252525),
              onPressed: () => _addCategory(selectedType),
              icon: const Icon(Icons.add),
              label: const Text('添加分类'),
            ),
    );
  }
}
