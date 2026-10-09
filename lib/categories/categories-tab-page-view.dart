import 'package:flutter/material.dart';
import 'package:piggybank/categories/categories-tab-page-edit.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/wallet.dart';
import 'package:piggybank/records/edit-record-page.dart';
import 'package:piggybank/records/components/transfer_wallet_selector.dart';
import 'package:piggybank/services/database/database-interface.dart';
import 'package:piggybank/services/service-config.dart';

import 'categories-grid.dart';
import 'category-ordering.dart';

class CategoryTabPageView extends StatefulWidget {
  const CategoryTabPageView({
    super.key,
    this.goToEditMovementPage,
    this.initialTabIndex = 0,
    this.initialDate,
  });

  final bool? goToEditMovementPage;
  final int initialTabIndex;
  final DateTime? initialDate;

  @override
  CategoryTabPageViewState createState() => CategoryTabPageViewState();
}

class CategoryTabPageViewState extends State<CategoryTabPageView> {
  List<Category?>? _categories;
  final DatabaseInterface database = ServiceConfig.database;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    final categories = await database.getAllCategories();
    categories.removeWhere(
      (category) => category == null || category.isArchived,
    );
    sortCategoriesSystemFirst(categories);
    if (mounted) setState(() => _categories = categories);
  }

  /// Called by the records tab when returning from a record change.
  Future<void> refreshCategories() => _fetchCategories();

  Future<void> _openCategoryManagement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TabCategories()),
    );
    await _fetchCategories();
  }

  void _openTransferEditPage(Wallet origin, Wallet destination) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditRecordPage(
          initialWallet: origin,
          initialDestinationWallet: destination,
          isTransferFlow: true,
          initialDate: widget.initialDate,
        ),
      ),
    );
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
    final showTransferTab =
        widget.goToEditMovementPage == true && ServiceConfig.walletsEnabled;
    final tabCount = showTransferTab ? 3 : 2;
    final initialIndex = widget.initialTabIndex.clamp(0, tabCount - 1).toInt();

    return DefaultTabController(
      length: tabCount,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: headerColor,
          foregroundColor: headerForeground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 62,
          titleSpacing: 10,
          title: TabBar(
            indicatorColor: headerForeground,
            indicatorWeight: 3,
            labelColor: headerForeground,
            unselectedLabelColor: headerMuted,
            labelStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            tabs: [
              const Tab(text: '支出'),
              const Tab(text: '收入'),
              if (showTransferTab) const Tab(text: '转账'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: headerForeground,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('取消', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        body: _categories == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  CategoriesGrid(
                    _categories!
                        .where(
                          (category) =>
                              category!.categoryType == CategoryType.expense,
                        )
                        .toList(),
                    goToEditMovementPage: widget.goToEditMovementPage,
                    initialDate: widget.initialDate,
                    onManageCategories: _openCategoryManagement,
                  ),
                  CategoriesGrid(
                    _categories!
                        .where(
                          (category) =>
                              category!.categoryType == CategoryType.income,
                        )
                        .toList(),
                    goToEditMovementPage: widget.goToEditMovementPage,
                    initialDate: widget.initialDate,
                    onManageCategories: _openCategoryManagement,
                  ),
                  if (showTransferTab)
                    TransferWalletSelector(onContinue: _openTransferEditPage),
                ],
              ),
      ),
    );
  }
}
