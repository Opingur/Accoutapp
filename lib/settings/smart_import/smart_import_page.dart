import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/models/wallet.dart';
import 'package:piggybank/shell.dart';
import 'package:piggybank/services/profile-service.dart';
import 'package:piggybank/services/service-config.dart';
import 'package:piggybank/services/smart_import_service.dart';

enum _SmartImportPreviewFilter { attention, all }

/// Safe CSV/XLSX import workflow. Parsing remains read-only until the user
/// completes the explicit two-step confirmation at the bottom of this page.
class SmartImportPage extends StatefulWidget {
  const SmartImportPage({super.key});

  @override
  State<SmartImportPage> createState() => _SmartImportPageState();
}

class _SmartImportPageState extends State<SmartImportPage> {
  SmartImportWorkbook? _workbook;
  SmartImportTable? _table;
  SmartImportMapping? _mapping;
  SmartImportPreview? _preview;
  List<Category?> _categories = const [];
  List<Wallet> _wallets = const [];
  List<Record?> _records = const [];
  Wallet? _defaultWallet;
  String? _fileName;
  String? _error;
  bool _loading = false;
  var _previewFilter = _SmartImportPreviewFilter.attention;

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'xlsx'],
      );
      final selected = result.isNotEmpty ? result.single : null;
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      final extension = selected.extension ?? selected.name.split('.').last;
      final workbook = SmartImportService.parseFileBytes(
        bytes,
        extension: extension,
      );
      final table = workbook.preferredTable;
      if (table == null || table.headers.isEmpty) {
        throw const FormatException('文件中没有可导入的表头和数据');
      }
      final profileId = ProfileService.instance.activeProfileId;
      final categoriesFuture = ServiceConfig.database.getAllCategories();
      final walletsFuture = ServiceConfig.database.getAllWallets(
        profileId: profileId,
      );
      final recordsFuture = ServiceConfig.database.getAllRecords(
        profileId: profileId,
      );
      final defaultWalletFuture = ServiceConfig.database.getDefaultWallet();
      _categories = await categoriesFuture;
      _wallets = await walletsFuture;
      _records = await recordsFuture;
      _defaultWallet = await defaultWalletFuture;
      _applyTable(workbook, table);
      _fileName = selected.name;
    } catch (error) {
      _error = '无法读取文件：$error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyTable(SmartImportWorkbook workbook, SmartImportTable table) {
    _workbook = workbook;
    _table = table;
    _mapping = SmartImportService.autoMap(table.headers);
    _rebuildPreview();
  }

  void _rebuildPreview() {
    final table = _table;
    final mapping = _mapping;
    if (table == null || mapping == null) return;
    _preview = SmartImportService.buildPreview(
      table: table,
      mapping: mapping,
      categories: _categories,
      wallets: _wallets,
      existingRecords: _records,
      defaultWallet: _defaultWallet,
    );
  }

  void _setMapping(SmartImportField field, String? column) {
    setState(() {
      _mapping!.set(field, column);
      _rebuildPreview();
    });
  }

  List<Category> _categoriesFor(SmartImportCandidate candidate) {
    final type = candidate.type == SmartImportTransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    final categories = _categories
        .whereType<Category>()
        .where(
          (category) => !category.isArchived && category.categoryType == type,
        )
        .toList();
    categories.sort((left, right) {
      if (left.isSystem != right.isSystem) return left.isSystem ? -1 : 1;
      return (left.sortOrder ?? 0).compareTo(right.sortOrder ?? 0);
    });
    return categories;
  }

  List<Wallet> get _activeWallets =>
      _wallets.where((wallet) => !wallet.isArchived).toList();

  Widget _pickerList(BuildContext context, List<Widget> children) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .55,
      child: ListView(children: children),
    ),
  );

  void _applyCategory(
    SmartImportCandidate candidate,
    Category category, {
    required bool sameTitle,
    required bool sameSourceCategory,
  }) {
    final targets = _preview!.candidates.where((item) {
      if (sameTitle && item.title != candidate.title) return false;
      if (sameSourceCategory &&
          item.sourceCategory != candidate.sourceCategory) {
        return false;
      }
      return true;
    });
    setState(() {
      for (final target in targets) {
        if (target.type == candidate.type) {
          target.suggestedCategory = category;
          target.issues.removeWhere((issue) => issue == '待确认：未匹配分类');
        }
      }
    });
  }

  Future<void> _chooseCategory(SmartImportCandidate candidate) async {
    if (candidate.type == null ||
        candidate.type == SmartImportTransactionType.transfer) {
      return;
    }
    final category = await showModalBottomSheet<Category>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => _pickerList(context, [
        const ListTile(title: Text('选择分类')),
        ..._categoriesFor(candidate).map(
          (item) => ListTile(
            title: Text(item.name ?? ''),
            onTap: () => Navigator.pop(context, item),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('创建自定义分类'),
          onTap: () => Navigator.pop(
            context,
            Category('', categoryType: CategoryType.expense),
          ),
        ),
      ]),
    );
    if (!mounted) return;
    if (category != null && (category.name?.isNotEmpty ?? false)) {
      _applyCategory(
        candidate,
        category,
        sameTitle: false,
        sameSourceCategory: false,
      );
      return;
    }
    if (category == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建自定义分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确认创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final duplicate = _categoriesFor(candidate)
        .any((item) => item.name == name);
    _applyCategory(
      candidate,
      duplicate
          ? _categoriesFor(candidate).firstWhere((item) => item.name == name)
          : Category(
              name,
              categoryType: candidate.type == SmartImportTransactionType.income
                  ? CategoryType.income
                  : CategoryType.expense,
            ),
      sameTitle: false,
      sameSourceCategory: false,
    );
  }

  Future<void> _chooseWallet(
    SmartImportCandidate candidate, {
    required bool destination,
  }) async {
    final wallet = await showModalBottomSheet<Wallet>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => _pickerList(context, [
        ListTile(title: Text(destination ? '选择转入钱包' : '选择钱包')),
        ..._activeWallets.map(
          (item) => ListTile(
            title: Text(item.name),
            onTap: () => Navigator.pop(context, item),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('创建新钱包'),
          onTap: () => Navigator.pop(context, Wallet('')),
        ),
      ]),
    );
    if (!mounted) return;
    if (wallet != null && wallet.name.isNotEmpty) {
      setState(() {
        if (destination) {
          candidate.transferWallet = wallet;
        } else {
          candidate.wallet = wallet;
        }
        candidate.issues.removeWhere((issue) => issue.startsWith('待确认：'));
      });
      return;
    }
    if (wallet == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建新钱包'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入钱包名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确认创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final matches = _activeWallets.where((item) => item.name == name).toList();
    final target = matches.isEmpty
        ? Wallet(name, profileId: ProfileService.instance.activeProfileId)
        : matches.first;
    setState(() {
      if (matches.isEmpty) _wallets = [..._wallets, target];
      if (destination) {
        candidate.transferWallet = target;
      } else {
        candidate.wallet = target;
      }
      candidate.issues.removeWhere((issue) => issue.startsWith('待确认：'));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入 CSV / Excel')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _table == null
          ? _buildPicker()
          : _buildPreview(),
      bottomNavigationBar: _loading || _table == null
          ? null
          : _buildConfirmBar(),
    );
  }

  Widget _buildConfirmBar() {
    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: FilledButton.icon(
            onPressed: _confirmImport,
            icon: const Icon(Icons.upload),
            label: const Text('确认导入'),
          ),
        ),
      ),
    );
  }

  Widget _buildPicker() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.upload_file_outlined, size: 56),
          const SizedBox(height: 16),
          const Text(
            '选择 CSV 或 Excel 流水文件',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '将先识别字段、分类、钱包和重复账单。预览期间不会修改任何账单数据。',
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('选择文件'),
          ),
        ],
      ),
    ),
  );

  Widget _buildPreview() {
    final workbook = _workbook!;
    final table = _table!;
    final preview = _preview!;
    final displayedCandidates = _previewFilter == _SmartImportPreviewFilter.all
        ? preview.candidates
        : preview.candidates
              .where(
                (candidate) => candidate.state != SmartImportRowState.ready,
              )
              .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(_fileName ?? '', style: Theme.of(context).textTheme.titleMedium),
        if (workbook.tables.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<SmartImportTable>(
            initialValue: table,
            decoration: const InputDecoration(labelText: '导入工作表'),
            items: workbook.tables
                .map(
                  (item) =>
                      DropdownMenuItem(value: item, child: Text(item.name)),
                )
                .toList(),
            onChanged: (selected) {
              if (selected == null) return;
              setState(() => _applyTable(workbook, selected));
            },
          ),
          const SizedBox(height: 8),
          const Text('仅选择包含逐笔账单的工作表；分类汇总、月度汇总和图表分析不会作为账单导入。'),
        ],
        const SizedBox(height: 20),
        Text('字段映射', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...SmartImportField.values.map(
          (field) => _mappingRow(field, table.headers),
        ),
        if (!_mapping!.hasRequiredFields)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('日期和金额为必填映射项。', style: TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 20),
        Text('导入预览', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _summary(preview),
        const SizedBox(height: 12),
        const Text('默认仅显示需要处理的账单。正常账单只计入汇总；点击确认导入后仍会显示最终汇总，二次确认前不会写入数据库。'),
        const SizedBox(height: 12),
        _buildPreviewFilter(preview),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _showBulkCategoryMapping,
              icon: const Icon(Icons.category_outlined),
              label: const Text('批量分类'),
            ),
            OutlinedButton.icon(
              onPressed: _showBulkWalletMapping,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('批量钱包映射'),
            ),
            OutlinedButton.icon(
              onPressed: _skipConfirmedDuplicates,
              icon: const Icon(Icons.playlist_remove),
              label: const Text('跳过数据库重复'),
            ),
            OutlinedButton.icon(
              onPressed: () => _resolveSuspectedDuplicates(
                SmartImportDuplicateDecision.keep,
              ),
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('保留全部疑似重复'),
            ),
            OutlinedButton.icon(
              onPressed: () => _resolveSuspectedDuplicates(
                SmartImportDuplicateDecision.skip,
              ),
              icon: const Icon(Icons.playlist_remove),
              label: const Text('跳过全部疑似重复'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (displayedCandidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('没有待处理账单，可以直接确认导入。')),
          )
        else
          ...displayedCandidates.map(_candidateTile),
      ],
    );
  }

  Widget _buildPreviewFilter(SmartImportPreview preview) {
    Widget option(_SmartImportPreviewFilter filter, String label) {
      final selected = _previewFilter == filter;
      return Expanded(
        child: selected
            ? FilledButton(
                onPressed: () => setState(() => _previewFilter = filter),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: () => setState(() => _previewFilter = filter),
                child: Text(label),
              ),
      );
    }

    return Row(
      children: [
        option(
          _SmartImportPreviewFilter.attention,
          '待处理 ${preview.attentionRows}',
        ),
        const SizedBox(width: 8),
        option(_SmartImportPreviewFilter.all, '查看全部 ${preview.totalRows}'),
      ],
    );
  }

  Widget _mappingRow(SmartImportField field, List<String> headers) {
    final value = _mapping![field];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String?>(
        key: ValueKey('${field.name}:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: _fieldLabel(field)),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('不映射')),
          ...headers.map(
            (header) =>
                DropdownMenuItem<String?>(value: header, child: Text(header)),
          ),
        ],
        onChanged: (column) => _setMapping(field, column),
      ),
    );
  }

  Widget _summary(SmartImportPreview preview) {
    final currency = NumberFormat('#,##0.00');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('总行数 ${preview.totalRows}'),
            Text('可直接导入 ${preview.validRows}'),
            Text('收入 ${currency.format(preview.incomeTotal)}'),
            Text('支出 ${currency.format(preview.expenseTotal)}'),
            Text('转账 ${preview.transferCount}'),
            Text('待分类 ${preview.needsCategory}'),
            Text('疑似重复 ${preview.possibleDuplicates}'),
            Text('待映射钱包 ${preview.needsWallet}'),
            Text('错误 ${preview.errors}'),
            Text('已跳过 ${preview.skippedRows}'),
            Text('待处理 ${preview.unresolvedRows}'),
          ],
        ),
      ),
    );
  }

  void _showIssues(SmartImportCandidate candidate) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('记录提示'),
        content: Text(candidate.issues.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDuplicateDecision(SmartImportCandidate candidate) async {
    final decision = await showDialog<SmartImportDuplicateDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('处理重复账单'),
        content: const Text('“保留”会明确写入此条，即使它与已有账单完全相同。请仅在确认这是两笔真实消费时使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, SmartImportDuplicateDecision.skip),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, SmartImportDuplicateDecision.keep),
            child: const Text('保留导入'),
          ),
        ],
      ),
    );
    if (decision != null && mounted) {
      setState(() => candidate.duplicateDecision = decision);
    }
  }

  void _skipConfirmedDuplicates() {
    setState(() {
      for (final candidate in _preview!.candidates) {
        if (candidate.duplicate == SmartImportDuplicate.exactExisting) {
          candidate.duplicateDecision = SmartImportDuplicateDecision.skip;
        }
      }
    });
  }

  void _resolveSuspectedDuplicates(SmartImportDuplicateDecision decision) {
    setState(() {
      for (final candidate in _preview!.candidates) {
        if (candidate.requiresDuplicateDecision &&
            candidate.duplicateDecision ==
                SmartImportDuplicateDecision.undecided) {
          candidate.duplicateDecision = decision;
        }
      }
    });
  }

  Future<Category?> _pickExistingCategory(SmartImportCandidate candidate) {
    return showModalBottomSheet<Category>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _pickerList(
        context,
        _categoriesFor(candidate)
            .map(
              (category) => ListTile(
                title: Text(category.name ?? ''),
                onTap: () => Navigator.pop(context, category),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _showBulkCategoryMapping() async {
    final groups = <String, List<SmartImportCandidate>>{};
    for (final candidate in _preview!.candidates) {
      if (candidate.type == null ||
          candidate.type == SmartImportTransactionType.transfer) {
        continue;
      }
      final type = candidate.type!.name;
      if (candidate.sourceCategory.isNotEmpty) {
        groups
            .putIfAbsent('分类：${candidate.sourceCategory}#$type', () => [])
            .add(candidate);
      }
      if (candidate.title.isNotEmpty) {
        groups
            .putIfAbsent('标题：${candidate.title}#$type', () => [])
            .add(candidate);
      }
    }
    final key = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _pickerList(
        context,
        groups.entries
            .map(
              (entry) => ListTile(
                title: Text(entry.key.split('#').first),
                subtitle: Text('${entry.value.length} 条账单'),
                onTap: () => Navigator.pop(context, entry.key),
              ),
            )
            .toList(),
      ),
    );
    if (key == null || !mounted) return;
    final targets = groups[key]!;
    final category = await _pickExistingCategory(targets.first);
    if (category == null || !mounted) return;
    setState(() {
      for (final candidate in targets) {
        candidate.suggestedCategory = category;
        candidate.issues.removeWhere((issue) => issue == '待确认：未匹配分类');
      }
    });
  }

  Future<void> _showBulkWalletMapping() async {
    final groups = <String, List<SmartImportCandidate>>{};
    for (final candidate in _preview!.candidates) {
      if (candidate.sourceWallet.isNotEmpty) {
        groups.putIfAbsent(candidate.sourceWallet, () => []).add(candidate);
      }
    }
    if (groups.isEmpty) return;
    final source = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _pickerList(
        context,
        groups.entries
            .map(
              (entry) => ListTile(
                title: Text(entry.key),
                subtitle: Text('${entry.value.length} 条账单'),
                onTap: () => Navigator.pop(context, entry.key),
              ),
            )
            .toList(),
      ),
    );
    if (source == null || !mounted) return;
    var wallet = await showModalBottomSheet<Wallet>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _pickerList(context, [
        ..._activeWallets.map(
          (item) => ListTile(
            title: Text(item.name),
            onTap: () => Navigator.pop(context, item),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('创建新钱包'),
          onTap: () => Navigator.pop(context, Wallet('')),
        ),
      ]),
    );
    if (wallet == null || !mounted) return;
    if (wallet.name.isEmpty) {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('创建新钱包'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '输入钱包名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('确认创建'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty || !mounted) return;
      final matches = _activeWallets
          .where((item) => item.name == name)
          .toList();
      wallet = matches.isEmpty
          ? Wallet(name, profileId: ProfileService.instance.activeProfileId)
          : matches.first;
      if (matches.isEmpty) {
        setState(() => _wallets = [..._wallets, wallet!]);
      }
    }
    setState(() {
      for (final candidate in groups[source]!) {
        candidate.wallet = wallet;
        candidate.issues.removeWhere((issue) => issue.startsWith('待确认：'));
      }
    });
  }

  Future<void> _confirmImport() async {
    final preview = _preview!;
    final profileId = ProfileService.instance.activeProfileId;
    final records = await ServiceConfig.database.getAllRecords(
      profileId: profileId,
    );
    SmartImportService.refreshDuplicates(
      preview.candidates,
      records.whereType<Record>(),
    );
    if (mounted) setState(() {});

    final unresolved = preview.candidates
        .where((candidate) => !candidate.isSkipped && !candidate.canCommit)
        .toList();
    if (unresolved.isNotEmpty) {
      setState(() => _previewFilter = _SmartImportPreviewFilter.attention);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('还有未处理账单'),
          content: Text(
            '仍有 ${unresolved.length} 条记录需要处理。已自动切换到“待处理”列表，请查看每条状态和原因后修正、保留重复或跳过。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final importable = preview.candidates
        .where((candidate) => candidate.canCommit)
        .toList();
    if (importable.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可导入的账单。')));
      return;
    }
    final newCategories = <Category>{
      for (final candidate in importable)
        if (candidate.suggestedCategory != null &&
            !candidate.suggestedCategory!.isSystem &&
            !_categories.whereType<Category>().contains(
              candidate.suggestedCategory,
            ))
          candidate.suggestedCategory!,
    };
    final newWallets = <Wallet>{
      for (final candidate in importable) ...[
        if (candidate.wallet != null && candidate.wallet!.id == null)
          candidate.wallet!,
        if (candidate.transferWallet != null &&
            candidate.transferWallet!.id == null)
          candidate.transferWallet!,
      ],
    };
    final currency = NumberFormat('#,##0.00');
    final income = importable
        .where(
          (candidate) => candidate.type == SmartImportTransactionType.income,
        )
        .fold(0.0, (sum, candidate) => sum + candidate.amount!);
    final expense = importable
        .where(
          (candidate) => candidate.type == SmartImportTransactionType.expense,
        )
        .fold(0.0, (sum, candidate) => sum + candidate.amount!);
    final transfers = importable
        .where(
          (candidate) => candidate.type == SmartImportTransactionType.transfer,
        )
        .length;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最终确认导入'),
        content: Text(
          '总记录 ${preview.totalRows} 笔\n'
          '实际写入 ${importable.length} 笔\n'
          '跳过 ${preview.totalRows - importable.length} 笔\n'
          '收入 ${currency.format(income)}\n'
          '支出 ${currency.format(expense)}\n'
          '转账 $transfers 笔\n'
          '新增分类 ${newCategories.length} 个\n'
          '新增钱包 ${newWallets.length} 个\n\n'
          '确认后将以一个数据库事务完成写入。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认写入'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final result = await ServiceConfig.database.commitSmartImport(
        preview.candidates,
        profileId: profileId,
        timeZoneName: ServiceConfig.localTimezone,
      );
      await ShellState.instance?.refreshImportedData();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '导入成功 ${result.imported} 笔\n'
            '跳过 ${result.skipped} 笔\n'
            '新增分类 ${result.createdCategories} 个\n'
            '新增钱包 ${result.createdWallets} 个\n'
            '收入 ${currency.format(result.incomeTotal)}\n'
            '支出 ${currency.format(result.expenseTotal)}\n'
            '转账 ${result.transferCount} 笔',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败，已回滚所有更改：$error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _candidateTile(SmartImportCandidate candidate) {
    final isProblem = candidate.state != SmartImportRowState.ready;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    candidate.title.isEmpty ? '（无标题）' : candidate.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(NumberFormat('#,##0.00').format(candidate.amount ?? 0)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '原始第 ${candidate.sourceRow} 行 · '
              '${candidate.dateTime == null ? '日期无效' : DateFormat('yyyy-MM-dd HH:mm:ss').format(candidate.dateTime!)} · ${candidate.typeLabel}',
            ),
            Text(
              '原分类：${candidate.sourceCategory.ifEmpty('—')}  新分类：${candidate.categoryLabel}',
            ),
            Text(
              '钱包：${candidate.wallet?.name ?? candidate.sourceWallet.ifEmpty('待映射')}'
              '${candidate.type == SmartImportTransactionType.transfer ? '  → ${candidate.transferWallet?.name ?? candidate.sourceTransferWallet.ifEmpty('待映射')}' : ''}',
            ),
            const SizedBox(height: 6),
            Text(
              candidate.stateLabel,
              style: TextStyle(
                color: isProblem ? colorScheme.error : colorScheme.primary,
              ),
            ),
            if (isProblem)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _stateReason(candidate),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (candidate.issues.isNotEmpty)
              TextButton.icon(
                onPressed: () => _showIssues(candidate),
                icon: const Icon(Icons.info_outline),
                label: const Text('查看提示'),
              ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (candidate.type != SmartImportTransactionType.transfer &&
                    candidate.type != null)
                  TextButton(
                    onPressed: () => _chooseCategory(candidate),
                    child: const Text('修改分类'),
                  ),
                TextButton(
                  onPressed: () => _chooseWallet(candidate, destination: false),
                  child: const Text('选择钱包'),
                ),
                if (candidate.type == SmartImportTransactionType.transfer)
                  TextButton(
                    onPressed: () =>
                        _chooseWallet(candidate, destination: true),
                    child: const Text('选择转入钱包'),
                  ),
                if (candidate.duplicate != SmartImportDuplicate.none)
                  TextButton(
                    onPressed: () => _chooseDuplicateDecision(candidate),
                    child: const Text('处理重复'),
                  ),
                TextButton(
                  onPressed: () =>
                      setState(() => candidate.skipped = !candidate.skipped),
                  child: Text(candidate.skipped ? '恢复此条' : '跳过此条'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _stateReason(SmartImportCandidate candidate) {
    return switch (candidate.state) {
      SmartImportRowState.needsCategory => '未能匹配到现有分类，请选择分类、创建自定义分类或跳过。',
      SmartImportRowState.needsWallet => '未能匹配到钱包，请选择钱包、确认创建新钱包或跳过。',
      SmartImportRowState.suspectedDuplicate =>
        candidate.duplicate == SmartImportDuplicate.inFile
            ? '同一文件中存在相同完整账单信息。不会自动丢弃，请确认保留导入或跳过。'
            : '与已有账单或缺少精确时间的账单相似。不会自动丢弃，请确认保留导入或跳过。',
      SmartImportRowState.duplicate => '数据库中已有完全相同账单，默认跳过；如确认是独立消费，可选择保留导入。',
      SmartImportRowState.skipped =>
        candidate.duplicate == SmartImportDuplicate.exactExisting
            ? '已按数据库重复保护默认跳过。可选择“处理重复”后保留导入。'
            : '此条已选择跳过，不会写入数据库。',
      SmartImportRowState.error => '此条数据无效，请查看提示后修正或跳过。',
      SmartImportRowState.ready => '',
    };
  }

  String _fieldLabel(SmartImportField field) => switch (field) {
    SmartImportField.date => '日期 *',
    SmartImportField.time => '时间',
    SmartImportField.type => '类型',
    SmartImportField.category => '分类',
    SmartImportField.title => '标题',
    SmartImportField.description => '备注',
    SmartImportField.amount => '金额 *',
    SmartImportField.wallet => '钱包',
    SmartImportField.transferWallet => '转入钱包',
    SmartImportField.recurrence => '是否周期账单',
  };
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
