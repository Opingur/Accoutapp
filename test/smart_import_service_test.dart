import 'dart:convert';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enough_convert/gbk.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/models/wallet.dart';
import 'package:piggybank/services/smart_import_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Etc/UTC'));
  });

  final dining = Category(
    '餐饮',
    categoryType: CategoryType.expense,
    isSystem: true,
  );
  final transport = Category(
    '交通',
    categoryType: CategoryType.expense,
    isSystem: true,
  );
  final other = Category(
    '其他',
    categoryType: CategoryType.expense,
    isSystem: true,
  );
  final salary = Category(
    '工资',
    categoryType: CategoryType.income,
    isSystem: true,
  );
  final cash = Wallet('现金')..id = 1;
  final bank = Wallet('银行卡')..id = 2;

  SmartImportPreview previewFor(
    String csv, {
    List<Record?> existing = const [],
  }) {
    final workbook = SmartImportService.parseFileBytes(
      utf8.encode(csv),
      extension: 'csv',
    );
    final table = workbook.preferredTable!;
    return SmartImportService.buildPreview(
      table: table,
      mapping: SmartImportService.autoMap(table.headers),
      categories: [dining, transport, other, salary],
      wallets: [cash, bank],
      existingRecords: existing,
      defaultWallet: cash,
    );
  }

  test('parses UTF-8 BOM and keeps title separate from a mapped category', () {
    final preview = previewFor(
      '\uFEFF日期,时间,类型,分类,标题,金额,钱包\n'
      '2026-10-01,12:34:56.789,支出,Food,肯德基,34.00,现金',
    );
    final candidate = preview.candidates.single;

    expect(candidate.title, '肯德基');
    expect(candidate.sourceCategory, 'Food');
    expect(candidate.suggestedCategory, dining);
    expect(candidate.amount, 34);
    expect(candidate.dateTime, DateTime(2026, 10, 1, 12, 34, 56, 789));
    expect(candidate.state, SmartImportRowState.ready);
  });

  test('parses GBK Chinese CSV bytes', () {
    const csv = '日期,金额,标题,分类\n2026-10-01,-12.50,奶茶,Food';
    final workbook = SmartImportService.parseFileBytes(
      gbk.encode(csv),
      extension: 'csv',
    );
    final table = workbook.preferredTable!;
    final preview = SmartImportService.buildPreview(
      table: table,
      mapping: SmartImportService.autoMap(table.headers),
      categories: [dining, transport, other, salary],
      wallets: [cash, bank],
      existingRecords: const [],
      defaultWallet: cash,
    );

    expect(table.headers, containsAll(['日期', '金额', '标题', '分类']));
    expect(preview.candidates.single.title, '奶茶');
    expect(preview.candidates.single.suggestedCategory, dining);
  });

  test('reads Excel native date and time cells and chooses detail sheet', () {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', '账单明细');
    final sheet = excel['账单明细'];
    const headers = ['日期', '时间', '类型', '分类', '标题', '金额', '钱包'];
    for (var column = 0; column < headers.length; column++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
        TextCellValue(headers[column]),
      );
    }
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      DateCellValue(year: 2026, month: 10, day: 2),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1),
      const TimeCellValue(hour: 8, minute: 9, second: 10),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1),
      TextCellValue('支出'),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1),
      TextCellValue('交通'),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1),
      TextCellValue('校易行'),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1),
      DoubleCellValue(1.9),
    );
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1),
      TextCellValue('现金'),
    );
    excel['图表分析'].updateCell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      TextCellValue('分类支出'),
    );

    final bytes = excel.save()!;
    final workbook = SmartImportService.parseFileBytes(
      bytes,
      extension: 'xlsx',
    );
    final table = workbook.preferredTable!;
    final preview = SmartImportService.buildPreview(
      table: table,
      mapping: SmartImportService.autoMap(table.headers),
      categories: [dining, transport, other, salary],
      wallets: [cash, bank],
      existingRecords: const [],
      defaultWallet: cash,
    );

    expect(table.name, '账单明细');
    expect(workbook.tables.map((table) => table.name), ['账单明细']);
    expect(preview.candidates.single.dateTime, DateTime(2026, 10, 2, 8, 9, 10));
    expect(preview.candidates.single.suggestedCategory, transport);
  });

  test('uses title keywords only when the source category is absent', () {
    final preview = previewFor(
      '日期,金额,标题,分类\n'
      '2026-10-01,-1.90,校易行,\n'
      '2026-10-02,-12.00,肯德基,未知分类\n'
      '2026-10-03,-20.00,未知消费,',
    );

    expect(preview.candidates[0].suggestedCategory, transport);
    expect(preview.candidates[1].state, SmartImportRowState.needsCategory);
    expect(preview.candidates[2].state, SmartImportRowState.needsCategory);
  });

  test(
    'marks ambiguous dates, type conflicts, and incomplete transfers as errors',
    () {
      final preview = previewFor(
        '日期,类型,金额,标题,钱包,转入钱包\n'
        '01/02/2026,支出,10,日期歧义,现金,\n'
        '2026-10-01,收入,-30,冲突,现金,\n'
        '2026-10-02,转账,100,缺目标,现金,',
      );

      expect(
        preview.candidates.map((candidate) => candidate.state),
        everyElement(SmartImportRowState.error),
      );
    },
  );

  test('detects exact and possible duplicates without merging valid same-day records', () {
    final existing = Record(
      -20,
      '午餐',
      dining,
      DateTime.utc(2026, 10, 1, 12),
      walletId: 1,
      timeZoneName: 'Etc/UTC',
    );
    final preview = previewFor(
      '日期,时间,金额,标题,分类,钱包\n'
      '2026-10-01,12:00:00,-20,午餐,餐饮,现金\n'
      '2026-10-01,12:00:00,-20,午餐,餐饮,现金\n'
      '2026-10-01,12:00:00,-20,晚餐,餐饮,现金\n'
      '2026-10-01,,-20,午餐,餐饮,现金',
      existing: [existing],
    );

    expect(preview.candidates[0].duplicate, SmartImportDuplicate.exactExisting);
    expect(preview.candidates[1].duplicate, SmartImportDuplicate.exactExisting);
    expect(preview.candidates[2].duplicate, SmartImportDuplicate.none);
    expect(
      preview.candidates[3].duplicate,
      SmartImportDuplicate.possibleExisting,
    );
  });

  test(
    'maps transfer wallets and does not treat transfer as income or expense',
    () {
      final preview = previewFor(
        '日期,类型,金额,标题,钱包,转入钱包\n'
        '2026-10-03,转账,200,储蓄转入,现金,银行卡',
      );
      final candidate = preview.candidates.single;

      expect(candidate.type, SmartImportTransactionType.transfer);
      expect(candidate.wallet, cash);
      expect(candidate.transferWallet, bank);
      expect(candidate.state, SmartImportRowState.ready);
      expect(preview.incomeTotal, 0);
      expect(preview.expenseTotal, 0);
    },
  );
}
