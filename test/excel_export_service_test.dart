import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybank/models/category.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/services/excel_export_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Etc/UTC'));
  });

  group('ExcelExportService', () {
    final dining = Category('餐饮', categoryType: CategoryType.expense);
    final transport = Category('交通', categoryType: CategoryType.expense);
    final salary = Category('工资', categoryType: CategoryType.income);

    Record record(
      double value,
      String title,
      Category category,
      DateTime date, {
      String? description,
      int? walletId,
      int? transferWalletId,
      String? recurrencePatternId,
    }) => Record(
      value,
      title,
      category,
      date,
      description: description,
      walletId: walletId,
      transferWalletId: transferWalletId,
      recurrencePatternId: recurrencePatternId,
      timeZoneName: 'Etc/UTC',
    );

    test('creates, reparses and preserves the four report sheets', () async {
      final records = [
        record(
          -30,
          '肯德基',
          dining,
          DateTime.utc(2026, 10, 2, 12, 34, 56, 789),
          description: '午餐',
          walletId: 1,
          recurrencePatternId: 'monthly-lunch',
        ),
        record(-20, '地铁', transport, DateTime.utc(2026, 10, 3), walletId: 1),
        record(1000, '十月工资', salary, DateTime.utc(2026, 10, 5), walletId: 2),
        record(-50, '旧账单', dining, DateTime.utc(2026, 9, 30), walletId: 1),
        record(
          -200,
          '钱包转账',
          transport,
          DateTime.utc(2026, 10, 6),
          walletId: 1,
          transferWalletId: 2,
        ),
      ];

      final bytes = ExcelExportService.createWorkbook(
        records: records,
        period: ExcelExportPeriod.currentMonth(DateTime(2026, 10, 8)),
        walletNames: const {1: '现金钱包', 2: '储蓄钱包'},
      );
      final output = File(
        '${Directory.systemTemp.path}/oinkoin_excel_export_test.xlsx',
      );
      await output.writeAsBytes(bytes, flush: true);

      final workbook = Excel.decodeBytes(bytes);
      expect(
        workbook.tables.keys,
        containsAll([
          ExcelExportService.detailSheetName,
          ExcelExportService.categorySheetName,
          ExcelExportService.monthlySheetName,
          ExcelExportService.chartSheetName,
        ]),
      );

      final details = workbook[ExcelExportService.detailSheetName];
      expect(details.maxRows, 5); // Header plus four October records.
      expect(List.generate(10, (column) => _textAt(details, column, 0)), [
        '日期',
        '时间',
        '类型',
        '分类',
        '标题',
        '备注',
        '金额',
        '钱包',
        '转入钱包',
        '是否周期账单',
      ]);
      expect(_textAt(details, 2, 1), '转账');
      expect(_numberAt(details, 6, 1), 200);
      expect(_textAt(details, 7, 1), '现金钱包');
      expect(_textAt(details, 8, 1), '储蓄钱包');

      final date = _valueAt(details, 0, 4) as DateCellValue;
      final time = _valueAt(details, 1, 4) as TimeCellValue;
      expect((date.year, date.month, date.day), (2026, 10, 2));
      expect(
        time,
        const TimeCellValue(hour: 12, minute: 34, second: 56, millisecond: 789),
      );
      expect(_textAt(details, 2, 4), '支出');
      expect(_textAt(details, 3, 4), '餐饮');
      expect(_textAt(details, 4, 4), '肯德基');
      expect(_numberAt(details, 6, 4), 30);
      expect(_textAt(details, 7, 4), '现金钱包');
      expect(_textAt(details, 8, 4), '');
      expect(_textAt(details, 9, 4), '是');

      final categories = workbook[ExcelExportService.categorySheetName];
      expect(_textAt(categories, 0, 1), '餐饮');
      expect(_numberAt(categories, 2, 1), 30);
      expect(_textAt(categories, 0, 2), '交通');
      expect(_numberAt(categories, 2, 2), 20);
      expect(_textAt(categories, 0, 3), '工资');
      expect(_numberAt(categories, 2, 3), 1000);

      final monthly = workbook[ExcelExportService.monthlySheetName];
      expect(_textAt(monthly, 0, 1), '2026-10');
      expect(_numberAt(monthly, 1, 1), 1000);
      expect(_numberAt(monthly, 2, 1), 50);
      expect(_numberAt(monthly, 3, 1), 950);

      final archive = ZipDecoder().decodeBytes(bytes);
      final chartFiles = archive.files
          .where((entry) => entry.name.startsWith('xl/charts/chart'))
          .toList();
      expect(chartFiles, hasLength(2));
      final chartXml = chartFiles
          .map((entry) => entry.content as List<int>)
          .map(String.fromCharCodes)
          .join();
      expect(chartXml, contains('doughnutChart'));
      expect(chartXml, contains('barChart'));
    });

    test('groups more than six expense categories into 其他 for the chart', () {
      final categories = List.generate(
        7,
        (index) => Category('分类$index', categoryType: CategoryType.expense),
      );
      final bytes = ExcelExportService.createWorkbook(
        records: List.generate(
          categories.length,
          (index) => record(
            -(index + 1).toDouble(),
            '账单$index',
            categories[index],
            DateTime.utc(2026, 10, 1),
          ),
        ),
        period: ExcelExportPeriod.currentMonth(DateTime(2026, 10, 1)),
        walletNames: const {},
      );
      final workbook = Excel.decodeBytes(bytes);
      final sheet = workbook[ExcelExportService.chartSheetName];
      expect(sheet.maxRows, greaterThanOrEqualTo(8));
      expect(_textAt(sheet, 0, 7), '其他');
      expect(_numberAt(sheet, 1, 7), 1);
    });
  });
}

String _textAt(Sheet sheet, int column, int row) {
  final value = _valueAt(sheet, column, row);
  return (value as TextCellValue).value.toString();
}

CellValue? _valueAt(Sheet sheet, int column, int row) => sheet
    .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
    .value;

num _numberAt(Sheet sheet, int column, int row) {
  final value = _valueAt(sheet, column, row);
  return switch (value) {
    DoubleCellValue(:final value) => value,
    IntCellValue(:final value) => value,
    _ => throw StateError('Expected a numeric cell'),
  };
}
