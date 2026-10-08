import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel_community/excel_community.dart';
import 'package:enough_convert/gbk.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/models/wallet.dart';

/// Fields the safe import flow understands. A source column can be assigned to
/// each field in the preview UI without changing the source file.
enum SmartImportField {
  date,
  time,
  type,
  category,
  title,
  description,
  amount,
  wallet,
  transferWallet,
  recurrence,
}

enum SmartImportTransactionType { expense, income, transfer }

enum SmartImportDuplicate { none, exactExisting, possibleExisting, inFile }

/// A duplicate is never silently merged. Existing exact matches default to
/// [skip], while possible and in-file matches must be explicitly resolved.
enum SmartImportDuplicateDecision { undecided, skip, keep }

enum SmartImportRowState {
  ready,
  needsCategory,
  needsWallet,
  suspectedDuplicate,
  duplicate,
  skipped,
  error,
}

/// A selected CSV table or one worksheet in an XLSX file. Cell values stay
/// typed until the import preview parses them; formulas are deliberately not
/// evaluated or executed.
class SmartImportTable {
  final String name;
  final List<String> headers;
  final List<Map<String, Object?>> rows;

  const SmartImportTable({
    required this.name,
    required this.headers,
    required this.rows,
  });
}

class SmartImportWorkbook {
  final List<SmartImportTable> tables;

  const SmartImportWorkbook(this.tables);

  SmartImportTable? get preferredTable {
    for (final table in tables) {
      if (table.name == '账单明细') return table;
    }
    return tables.isEmpty ? null : tables.first;
  }
}

class SmartImportMapping {
  final Map<SmartImportField, String?> columns;

  SmartImportMapping([Map<SmartImportField, String?>? columns])
    : columns = {
        for (final field in SmartImportField.values) field: null,
        ...?columns,
      };

  String? operator [](SmartImportField field) => columns[field];

  void set(SmartImportField field, String? value) => columns[field] = value;

  bool get hasRequiredFields =>
      this[SmartImportField.date] != null &&
      this[SmartImportField.amount] != null;
}

/// A single input row after parsing. It is intentionally not a [Record]: no
/// database identifiers are allocated and this phase cannot write data.
class SmartImportCandidate {
  final int sourceRow;
  final DateTime? dateTime;
  final bool hasExplicitTime;
  final SmartImportTransactionType? type;
  final double? amount;
  final String title;
  final String description;
  final String sourceCategory;
  final String sourceWallet;
  final String sourceTransferWallet;
  final String recurrence;
  Category? suggestedCategory;
  Wallet? wallet;
  Wallet? transferWallet;
  final List<String> issues;
  SmartImportDuplicate duplicate;
  SmartImportDuplicateDecision duplicateDecision;
  bool skipped;

  SmartImportCandidate({
    required this.sourceRow,
    required this.dateTime,
    required this.hasExplicitTime,
    required this.type,
    required this.amount,
    required this.title,
    required this.description,
    required this.sourceCategory,
    required this.sourceWallet,
    required this.sourceTransferWallet,
    required this.recurrence,
    required this.suggestedCategory,
    required this.wallet,
    required this.transferWallet,
    required this.issues,
    this.duplicate = SmartImportDuplicate.none,
    this.duplicateDecision = SmartImportDuplicateDecision.undecided,
    this.skipped = false,
  });

  bool get requiresDuplicateDecision =>
      duplicate == SmartImportDuplicate.possibleExisting ||
      duplicate == SmartImportDuplicate.inFile;

  bool get isSkipped =>
      skipped || duplicateDecision == SmartImportDuplicateDecision.skip;

  bool get canCommit => state == SmartImportRowState.ready;

  SmartImportRowState get state {
    if (issues.any((issue) => issue.startsWith('错误：'))) {
      return SmartImportRowState.error;
    }
    if (isSkipped) return SmartImportRowState.skipped;
    if (requiresDuplicateDecision &&
        duplicateDecision == SmartImportDuplicateDecision.undecided) {
      return SmartImportRowState.suspectedDuplicate;
    }
    if (duplicate == SmartImportDuplicate.exactExisting) {
      return SmartImportRowState.duplicate;
    }
    if (type == SmartImportTransactionType.transfer &&
        (wallet == null || transferWallet == null)) {
      return SmartImportRowState.needsWallet;
    }
    if (type != SmartImportTransactionType.transfer &&
        suggestedCategory == null) {
      return SmartImportRowState.needsCategory;
    }
    if (wallet == null) return SmartImportRowState.needsWallet;
    return SmartImportRowState.ready;
  }

  String get typeLabel => switch (type) {
    SmartImportTransactionType.expense => '支出',
    SmartImportTransactionType.income => '收入',
    SmartImportTransactionType.transfer => '转账',
    null => '待确认',
  };

  String get categoryLabel => suggestedCategory?.name ?? '待分类';

  String get stateLabel => switch (state) {
    SmartImportRowState.ready => '已匹配',
    SmartImportRowState.needsCategory => '待分类',
    SmartImportRowState.needsWallet => '待映射钱包',
    SmartImportRowState.suspectedDuplicate => '疑似重复',
    SmartImportRowState.duplicate => '重复账单',
    SmartImportRowState.skipped => '已跳过',
    SmartImportRowState.error => '数据错误',
  };
}

/// The result returned only after a successful database transaction.
class SmartImportCommitResult {
  final int imported;
  final int skipped;
  final int createdCategories;
  final int createdWallets;
  final double incomeTotal;
  final double expenseTotal;
  final int transferCount;

  const SmartImportCommitResult({
    required this.imported,
    required this.skipped,
    required this.createdCategories,
    required this.createdWallets,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.transferCount,
  });
}

class SmartImportPreview {
  final List<SmartImportCandidate> candidates;

  const SmartImportPreview(this.candidates);

  int get totalRows => candidates.length;
  int get validRows =>
      candidates.where((candidate) => candidate.canCommit).length;
  int get skippedRows =>
      candidates.where((candidate) => candidate.isSkipped).length;
  int get expenseCount => candidates
      .where(
        (candidate) => candidate.type == SmartImportTransactionType.expense,
      )
      .length;
  int get incomeCount => candidates
      .where((candidate) => candidate.type == SmartImportTransactionType.income)
      .length;
  int get transferCount => candidates
      .where(
        (candidate) => candidate.type == SmartImportTransactionType.transfer,
      )
      .length;
  int get errors => candidates
      .where((candidate) => candidate.state == SmartImportRowState.error)
      .length;
  int get needsCategory => candidates
      .where(
        (candidate) => candidate.state == SmartImportRowState.needsCategory,
      )
      .length;
  int get possibleDuplicates => candidates
      .where(
        (candidate) =>
            candidate.duplicate == SmartImportDuplicate.possibleExisting,
      )
      .length;
  int get exactDuplicates => candidates
      .where((candidate) => candidate.duplicate != SmartImportDuplicate.none)
      .length;
  double get expenseTotal => candidates
      .where(
        (candidate) => candidate.type == SmartImportTransactionType.expense,
      )
      .fold(0, (sum, candidate) => sum + (candidate.amount ?? 0));
  double get incomeTotal => candidates
      .where((candidate) => candidate.type == SmartImportTransactionType.income)
      .fold(0, (sum, candidate) => sum + (candidate.amount ?? 0));
}

/// Pure parsing and preview service for CSV/XLSX imports.
///
/// It has no database dependency and cannot create categories, wallets, or
/// records. The next phase will consume only user-confirmed [SmartImportPreview]
/// candidates in a database transaction.
class SmartImportService {
  SmartImportService._();

  static const _legacyAliases = <String, String>{
    'food': '餐饮',
    'transport': '交通',
    'house': '居家',
    'salary': '工资',
  };

  static const _keywords = <String, List<String>>{
    '交通': ['校易行', '滴滴', '地铁', '公交', '打车', '车票', '火车'],
    '餐饮': ['烤肉', '肯德基', '美食广场', '早饭', '午饭', '晚饭', '餐厅', '外卖'],
    '零食': ['奶茶', '薯片', '零食'],
    '运动': ['哑铃', '单杠', '弹力带', '健身'],
    '服饰': ['衣服', '短裤', '帽子', '鞋'],
    '美容': ['理发', '剃须刀', '发泥', '护肤'],
    '数码': ['chatgpt', 'deepseek api', '鼠标', '键盘', '显示器'],
    '通讯': ['话费', '手机充值', '流量'],
    '住房': ['电费', '暖气', '房租', '水费'],
    '学习': ['买卷子', '刷课', '教材', '课程'],
  };

  static const _aliases = <SmartImportField, List<String>>{
    SmartImportField.date: [
      '日期',
      '交易日期',
      'date',
      'transactiondate',
      '日期时间',
      'datetime',
    ],
    SmartImportField.time: ['时间', '交易时间', 'time', 'transactiontime'],
    SmartImportField.type: ['类型', '收支类型', 'type', 'transactiontype'],
    SmartImportField.category: ['分类', '新分类', 'category'],
    SmartImportField.title: ['标题', '原title', '交易名称', '商品名称', 'title', 'name'],
    SmartImportField.description: ['备注', '说明', 'description', 'note', 'memo'],
    SmartImportField.amount: ['金额', '交易金额', 'amount', 'money', 'value'],
    SmartImportField.wallet: ['钱包', '账户', 'wallet', 'account'],
    SmartImportField.transferWallet: [
      '转入钱包',
      '目标账户',
      'transferwallet',
      'destinationwallet',
    ],
    SmartImportField.recurrence: ['是否周期账单', '周期账单', 'recurrence'],
  };

  static SmartImportWorkbook parseFileBytes(
    List<int> bytes, {
    required String extension,
  }) {
    final normalized = extension.toLowerCase().replaceFirst('.', '');
    return switch (normalized) {
      'csv' ||
      'tsv' ||
      'txt' => SmartImportWorkbook([_parseCsvBytes(bytes, name: 'CSV 数据')]),
      'xlsx' => _parseXlsx(bytes),
      _ => throw const FormatException('仅支持 CSV 或 XLSX 文件'),
    };
  }

  static SmartImportMapping autoMap(List<String> headers) {
    final mapping = SmartImportMapping();
    for (final field in SmartImportField.values) {
      final aliases = _aliases[field]!;
      mapping.set(
        field,
        headers.cast<String?>().firstWhere(
          (header) => header != null && aliases.contains(_headerKey(header)),
          orElse: () => null,
        ),
      );
    }
    return mapping;
  }

  static SmartImportPreview buildPreview({
    required SmartImportTable table,
    required SmartImportMapping mapping,
    required Iterable<Category?> categories,
    required Iterable<Wallet> wallets,
    required Iterable<Record?> existingRecords,
    Wallet? defaultWallet,
  }) {
    final availableCategories = categories.whereType<Category>().toList();
    final availableWallets = wallets.toList();
    final candidates = <SmartImportCandidate>[];

    for (var index = 0; index < table.rows.length; index++) {
      final row = table.rows[index];
      candidates.add(
        _parseCandidate(
          row: row,
          sourceRow: index + 2,
          mapping: mapping,
          categories: availableCategories,
          wallets: availableWallets,
          defaultWallet: defaultWallet,
        ),
      );
    }

    refreshDuplicates(candidates, existingRecords.whereType<Record>());
    return SmartImportPreview(candidates);
  }

  /// Reuses the first-stage duplicate rules immediately before committing so
  /// another write between preview and confirmation cannot create a duplicate.
  static void refreshDuplicates(
    Iterable<SmartImportCandidate> candidates,
    Iterable<Record> existingRecords,
  ) {
    final candidateList = candidates.toList();
    for (final candidate in candidateList) {
      candidate.duplicate = SmartImportDuplicate.none;
    }
    _markDuplicates(candidateList, existingRecords);
    for (final candidate in candidateList) {
      if (candidate.duplicate == SmartImportDuplicate.exactExisting &&
          candidate.duplicateDecision ==
              SmartImportDuplicateDecision.undecided) {
        candidate.duplicateDecision = SmartImportDuplicateDecision.skip;
      }
    }
  }

  static SmartImportTable _parseCsvBytes(
    List<int> bytes, {
    required String name,
  }) {
    String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      // GBK is still common in exports from Chinese desktop applications.
      text = gbk.decode(bytes);
    }
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final delimiter = _detectDelimiter(text);
    final rows = Csv(
      fieldDelimiter: delimiter,
      dynamicTyping: false,
    ).decode(text);
    return _tableFromRows(name, rows);
  }

  static SmartImportWorkbook _parseXlsx(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final tables = <SmartImportTable>[];
    final isOinkoinExport = excel.tables.containsKey('账单明细');
    for (final entry in excel.tables.entries) {
      // An Oinkoin report has derived sheets alongside its source records.
      // Only the detail sheet is safe to import; summary/chart values must
      // never be treated as new transactions.
      if (isOinkoinExport && entry.key != '账单明细') continue;
      final rows = entry.value.rows
          .map<List<Object?>>(
            (row) => row.map((cell) => _safeCellValue(cell?.value)).toList(),
          )
          .toList();
      final table = _tableFromRows(entry.key, rows);
      if (table.headers.isNotEmpty) tables.add(table);
    }
    if (tables.isEmpty) throw const FormatException('Excel 中没有可读取的工作表');
    return SmartImportWorkbook(tables);
  }

  static SmartImportTable _tableFromRows(
    String name,
    List<List<Object?>> rows,
  ) {
    final first = rows.indexWhere(
      (row) => row.any((cell) => _text(cell).isNotEmpty),
    );
    if (first < 0)
      return SmartImportTable(name: name, headers: const [], rows: const []);
    final headers = <String>[];
    for (var index = 0; index < rows[first].length; index++) {
      final raw = _text(rows[first][index]).trim();
      headers.add(raw.isEmpty ? '列${index + 1}' : raw);
    }
    final mappedRows = <Map<String, Object?>>[];
    for (final values in rows.skip(first + 1)) {
      if (values.every((value) => _text(value).trim().isEmpty)) continue;
      mappedRows.add({
        for (var column = 0; column < headers.length; column++)
          headers[column]: column < values.length ? values[column] : null,
      });
    }
    return SmartImportTable(name: name, headers: headers, rows: mappedRows);
  }

  static Object? _safeCellValue(CellValue? value) {
    if (value is FormulaCellValue) return null;
    return value;
  }

  static SmartImportCandidate _parseCandidate({
    required Map<String, Object?> row,
    required int sourceRow,
    required SmartImportMapping mapping,
    required List<Category> categories,
    required List<Wallet> wallets,
    required Wallet? defaultWallet,
  }) {
    final issues = <String>[];
    final date = _parseDateTime(
      row[mapping[SmartImportField.date]],
      row[mapping[SmartImportField.time]],
    );
    if (date.value == null) {
      issues.add('错误：缺少或无法确认的日期');
    } else if (date.ambiguous) {
      issues.add('错误：日期格式歧义，请确认日/月顺序');
    }

    final rawAmount = _parseAmount(row[mapping[SmartImportField.amount]]);
    if (rawAmount == null || rawAmount == 0) {
      issues.add('错误：缺少或无效金额');
    }

    final rawType = _text(row[mapping[SmartImportField.type]]);
    final type = _parseType(rawType, rawAmount);
    if (type == null) issues.add('错误：无法识别收支类型');
    if (type == SmartImportTransactionType.income && (rawAmount ?? 0) < 0) {
      issues.add('错误：类型“收入”与负数金额冲突');
    }

    final sourceCategory = _text(row[mapping[SmartImportField.category]])
        .trim();
    final title = _text(row[mapping[SmartImportField.title]]).trim();
    final description = _text(row[mapping[SmartImportField.description]])
        .trim();
    final sourceWallet = _text(row[mapping[SmartImportField.wallet]]).trim();
    final sourceTransferWallet = _text(
      row[mapping[SmartImportField.transferWallet]],
    ).trim();
    final recurrence = _text(row[mapping[SmartImportField.recurrence]]).trim();

    final category = type == SmartImportTransactionType.transfer
        ? null
        : _suggestCategory(
            sourceCategory: sourceCategory,
            title: title,
            type: type,
            categories: categories,
          );
    if (type != null &&
        type != SmartImportTransactionType.transfer &&
        category == null) {
      issues.add('待确认：未匹配分类');
    }

    final wallet =
        _findWallet(sourceWallet, wallets) ??
        (sourceWallet.isEmpty && type != SmartImportTransactionType.transfer
            ? defaultWallet
            : null);
    if (sourceWallet.isNotEmpty && wallet == null) {
      issues.add('待确认：未找到钱包“$sourceWallet”');
    }
    final transferWallet = _findWallet(sourceTransferWallet, wallets);
    if (type == SmartImportTransactionType.transfer &&
        (sourceWallet.isEmpty || sourceTransferWallet.isEmpty)) {
      issues.add('错误：转账必须提供来源和转入钱包');
    } else if (type == SmartImportTransactionType.transfer &&
        (wallet == null || transferWallet == null)) {
      issues.add('待确认：转账钱包尚未映射');
    }

    return SmartImportCandidate(
      sourceRow: sourceRow,
      dateTime: date.value,
      hasExplicitTime: date.hasExplicitTime,
      type: type,
      amount: rawAmount?.abs(),
      title: title,
      description: description,
      sourceCategory: sourceCategory,
      sourceWallet: sourceWallet,
      sourceTransferWallet: sourceTransferWallet,
      recurrence: recurrence,
      suggestedCategory: category,
      wallet: wallet,
      transferWallet: transferWallet,
      issues: issues,
    );
  }

  static Category? _suggestCategory({
    required String sourceCategory,
    required String title,
    required SmartImportTransactionType? type,
    required List<Category> categories,
  }) {
    if (type == null || type == SmartImportTransactionType.transfer)
      return null;
    final categoryType = type == SmartImportTransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    final normalizedSource = _key(sourceCategory);
    final alias = _legacyAliases[normalizedSource];
    final expected = alias ?? sourceCategory;

    for (final category in categories) {
      if (category.categoryType == categoryType &&
          _key(category.name ?? '') == _key(expected)) {
        return category;
      }
    }
    if (sourceCategory.isNotEmpty) return null;

    final normalizedTitle = _key(title);
    for (final entry in _keywords.entries) {
      if (!entry.value.any(
        (keyword) => normalizedTitle.contains(_key(keyword)),
      )) {
        continue;
      }
      for (final category in categories) {
        if (category.categoryType == categoryType &&
            _key(category.name ?? '') == _key(entry.key)) {
          return category;
        }
      }
    }
    return null;
  }

  static Wallet? _findWallet(String name, List<Wallet> wallets) {
    final target = _key(name);
    if (target.isEmpty) return null;
    for (final wallet in wallets) {
      if (_key(wallet.name) == target) return wallet;
    }
    return null;
  }

  static void _markDuplicates(
    List<SmartImportCandidate> candidates,
    Iterable<Record> existingRecords,
  ) {
    final existing = existingRecords.toList();
    for (var index = 0; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (candidate.dateTime == null ||
          candidate.amount == null ||
          candidate.type == null) {
        continue;
      }
      for (final record in existing) {
        if (!_sameCore(candidate, record)) continue;
        candidate.duplicate =
            candidate.hasExplicitTime &&
                _sameLocalDateTime(record.dateTime, candidate.dateTime!)
            ? SmartImportDuplicate.exactExisting
            : SmartImportDuplicate.possibleExisting;
        break;
      }
      if (candidate.duplicate != SmartImportDuplicate.none) continue;
      for (var prior = 0; prior < index; prior++) {
        final previous = candidates[prior];
        if (!_sameCandidates(candidate, previous)) continue;
        candidate.duplicate =
            candidate.hasExplicitTime && previous.hasExplicitTime
            ? SmartImportDuplicate.inFile
            : SmartImportDuplicate.possibleExisting;
        break;
      }
    }
  }

  static bool _sameCore(SmartImportCandidate candidate, Record record) {
    final candidateIsTransfer =
        candidate.type == SmartImportTransactionType.transfer;
    if (candidateIsTransfer != record.isTransfer ||
        (record.value ?? 0).abs() != candidate.amount ||
        _key(record.title ?? '') != _key(candidate.title) ||
        _key(record.description ?? '') != _key(candidate.description) ||
        record.walletId != candidate.wallet?.id ||
        record.transferWalletId != candidate.transferWallet?.id) {
      return false;
    }
    if (!candidateIsTransfer &&
        (_key(record.category?.name ?? '') !=
                _key(candidate.suggestedCategory?.name ?? '') ||
            record.category?.categoryType !=
                (candidate.type == SmartImportTransactionType.income
                    ? CategoryType.income
                    : CategoryType.expense))) {
      return false;
    }
    if (candidate.hasExplicitTime) {
      return _sameLocalDateTime(record.dateTime, candidate.dateTime!);
    }
    final local = record.dateTime;
    final expected = candidate.dateTime!;
    return local.year == expected.year &&
        local.month == expected.month &&
        local.day == expected.day;
  }

  static bool _sameCandidates(
    SmartImportCandidate first,
    SmartImportCandidate second,
  ) =>
      first.dateTime != null &&
      second.dateTime != null &&
      first.amount == second.amount &&
      first.type == second.type &&
      _key(first.title) == _key(second.title) &&
      _key(first.description) == _key(second.description) &&
      _key(first.suggestedCategory?.name ?? '') ==
          _key(second.suggestedCategory?.name ?? '') &&
      first.wallet?.id == second.wallet?.id &&
      first.transferWallet?.id == second.transferWallet?.id &&
      (first.hasExplicitTime && second.hasExplicitTime
          ? first.dateTime!.toUtc() == second.dateTime!.toUtc()
          : _sameDay(first.dateTime!, second.dateTime!));

  static bool _sameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static bool _sameLocalDateTime(DateTime first, DateTime second) =>
      _sameDay(first, second) &&
      first.hour == second.hour &&
      first.minute == second.minute &&
      first.second == second.second &&
      first.millisecond == second.millisecond;

  static SmartImportTransactionType? _parseType(String type, double? amount) {
    final normalized = _key(type);
    if (normalized.contains('转账') || normalized.contains('transfer')) {
      return SmartImportTransactionType.transfer;
    }
    if (normalized.contains('收入') || normalized.contains('income')) {
      return SmartImportTransactionType.income;
    }
    if (normalized.contains('支出') || normalized.contains('expense')) {
      return SmartImportTransactionType.expense;
    }
    if (normalized.isEmpty && amount != null) {
      return amount < 0
          ? SmartImportTransactionType.expense
          : SmartImportTransactionType.income;
    }
    return null;
  }

  static _ParsedDate _parseDateTime(Object? rawDate, Object? rawTime) {
    final date = _parseDate(rawDate);
    if (date.value == null || date.ambiguous) return date;
    final time = _parseTime(rawTime);
    if (time.invalid)
      return _ParsedDate(null, ambiguous: false, hasExplicitTime: false);
    final base = date.value!;
    return _ParsedDate(
      DateTime(
        base.year,
        base.month,
        base.day,
        time.hour,
        time.minute,
        time.second,
        time.millisecond,
      ),
      ambiguous: false,
      hasExplicitTime: date.hasExplicitTime || time.hasValue,
    );
  }

  static _ParsedDate _parseDate(Object? value) {
    if (value is DateCellValue) {
      return _ParsedDate(DateTime(value.year, value.month, value.day));
    }
    if (value is DateTimeCellValue) {
      return _ParsedDate(
        DateTime(
          value.year,
          value.month,
          value.day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
        ),
        hasExplicitTime:
            value.hour != 0 ||
            value.minute != 0 ||
            value.second != 0 ||
            value.millisecond != 0,
      );
    }
    if (value is num && value > 20000) {
      return _ParsedDate(
        DateTime(1899, 12, 30).add(
          Duration(milliseconds: (value * Duration.millisecondsPerDay).round()),
        ),
      );
    }
    final text = _text(value).trim();
    if (text.isEmpty) return const _ParsedDate(null);
    final iso = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?)?$',
    ).firstMatch(text);
    if (iso != null) {
      return _buildDate(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
        hour: int.tryParse(iso.group(4) ?? '') ?? 0,
        minute: int.tryParse(iso.group(5) ?? '') ?? 0,
        second: int.tryParse(iso.group(6) ?? '') ?? 0,
        millisecond: _millis(iso.group(7)),
        hasExplicitTime: iso.group(4) != null,
      );
    }
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(text);
    if (compact != null) {
      return _buildDate(
        int.parse(compact.group(1)!),
        int.parse(compact.group(2)!),
        int.parse(compact.group(3)!),
      );
    }
    final ambiguous = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$')
        .firstMatch(text);
    if (ambiguous != null) {
      final first = int.parse(ambiguous.group(1)!);
      final second = int.parse(ambiguous.group(2)!);
      if (first <= 12 && second <= 12)
        return const _ParsedDate(null, ambiguous: true);
      return first > 12
          ? _buildDate(int.parse(ambiguous.group(3)!), second, first)
          : _buildDate(int.parse(ambiguous.group(3)!), first, second);
    }
    return const _ParsedDate(null);
  }

  static _ParsedTime _parseTime(Object? value) {
    if (value is TimeCellValue) {
      return _ParsedTime(
        hour: value.hour,
        minute: value.minute,
        second: value.second,
        millisecond: value.millisecond,
        hasValue: true,
      );
    }
    if (value == null || _text(value).trim().isEmpty) {
      return const _ParsedTime();
    }
    if (value is DateTimeCellValue) {
      return _ParsedTime(
        hour: value.hour,
        minute: value.minute,
        second: value.second,
        millisecond: value.millisecond,
        hasValue: true,
      );
    }
    if (value is num && value >= 0 && value < 1) {
      final duration = Duration(
        milliseconds: (value * Duration.millisecondsPerDay).round(),
      );
      return _ParsedTime(
        hour: duration.inHours % 24,
        minute: duration.inMinutes % 60,
        second: duration.inSeconds % 60,
        millisecond: duration.inMilliseconds % 1000,
        hasValue: true,
      );
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?$')
        .firstMatch(_text(value).trim());
    if (match == null) return const _ParsedTime(invalid: true);
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '') ?? 0;
    if (hour > 23 || minute > 59 || second > 59)
      return const _ParsedTime(invalid: true);
    return _ParsedTime(
      hour: hour,
      minute: minute,
      second: second,
      millisecond: _millis(match.group(4)),
      hasValue: true,
    );
  }

  static _ParsedDate _buildDate(
    int year,
    int month,
    int day, {
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
    bool hasExplicitTime = false,
  }) {
    final date = DateTime(year, month, day, hour, minute, second, millisecond);
    if (date.year != year || date.month != month || date.day != day)
      return const _ParsedDate(null);
    return _ParsedDate(date, hasExplicitTime: hasExplicitTime);
  }

  static int _millis(String? value) =>
      value == null ? 0 : int.parse(value.padRight(3, '0'));

  static double? _parseAmount(Object? value) {
    if (value is num) return value.toDouble();
    var text = _text(value).trim();
    if (text.isEmpty) return null;
    final negative = text.startsWith('(') && text.endsWith(')');
    text = text.replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (text.contains(',') && text.contains('.')) {
      text = text.lastIndexOf(',') > text.lastIndexOf('.')
          ? text.replaceAll('.', '').replaceAll(',', '.')
          : text.replaceAll(',', '');
    } else if (text.contains(',') &&
        text.indexOf(',') == text.lastIndexOf(',') &&
        text.length - text.lastIndexOf(',') <= 3) {
      text = text.replaceAll(',', '.');
    } else {
      text = text.replaceAll(',', '');
    }
    final parsed = double.tryParse(text);
    return parsed == null ? null : (negative ? -parsed.abs() : parsed);
  }

  static String _detectDelimiter(String content) {
    final firstLine = content.split(RegExp(r'\r?\n')).first;
    final scores = <String, int>{
      ',': firstLine.split(',').length,
      ';': firstLine.split(';').length,
      '\t': firstLine.split('\t').length,
    };
    return scores.entries
        .reduce((left, right) => left.value >= right.value ? left : right)
        .key;
  }

  static String _headerKey(String value) =>
      _key(value).replaceAll(RegExp(r'[_\s]'), '');
  static String _key(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static String _text(Object? value) => switch (value) {
    null => '',
    TextCellValue(:final value) => value.toString(),
    IntCellValue(:final value) => value.toString(),
    DoubleCellValue(:final value) => value.toString(),
    BoolCellValue(:final value) => value.toString(),
    DateCellValue(:final year, :final month, :final day) =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    DateTimeCellValue() => '',
    TimeCellValue() => '',
    _ => value.toString(),
  };
}

class _ParsedDate {
  final DateTime? value;
  final bool ambiguous;
  final bool hasExplicitTime;
  const _ParsedDate(
    this.value, {
    this.ambiguous = false,
    this.hasExplicitTime = false,
  });
}

class _ParsedTime {
  final int hour;
  final int minute;
  final int second;
  final int millisecond;
  final bool hasValue;
  final bool invalid;
  const _ParsedTime({
    this.hour = 0,
    this.minute = 0,
    this.second = 0,
    this.millisecond = 0,
    this.hasValue = false,
    this.invalid = false,
  });
}
