import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';

/// The period selected by the user before an Excel export is created.
enum ExcelExportRange { currentMonth, currentYear, custom, all }

/// A date range used by [ExcelExportService]. Both boundaries are inclusive.
class ExcelExportPeriod {
  final ExcelExportRange range;
  final DateTime? from;
  final DateTime? to;

  const ExcelExportPeriod._(this.range, {this.from, this.to});

  factory ExcelExportPeriod.currentMonth(DateTime now) => ExcelExportPeriod._(
    ExcelExportRange.currentMonth,
    from: DateTime(now.year, now.month),
    to: DateTime(now.year, now.month + 1).subtract(const Duration(days: 1)),
  );

  factory ExcelExportPeriod.currentYear(DateTime now) => ExcelExportPeriod._(
    ExcelExportRange.currentYear,
    from: DateTime(now.year),
    to: DateTime(now.year + 1).subtract(const Duration(days: 1)),
  );

  factory ExcelExportPeriod.custom(DateTime from, DateTime to) =>
      ExcelExportPeriod._(
        ExcelExportRange.custom,
        from: _dayStart(from),
        to: _dayEnd(to),
      );

  const ExcelExportPeriod.all() : this._(ExcelExportRange.all);

  bool includes(DateTime value) {
    final local = value.toLocal();
    return (from == null || !local.isBefore(from!)) &&
        (to == null || !local.isAfter(to!));
  }

  String get fileNamePart => switch (range) {
    ExcelExportRange.currentMonth =>
      '${from!.year}${from!.month.toString().padLeft(2, '0')}',
    ExcelExportRange.currentYear => '${from!.year}',
    ExcelExportRange.custom => '${_datePart(from!)}-${_datePart(to!)}',
    ExcelExportRange.all => '全部账单',
  };

  static DateTime _dayStart(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _dayEnd(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  static String _datePart(DateTime value) =>
      '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
}

/// Creates the data-only Excel workbook used by data management.
///
/// The service does not write to the database. Callers pass records belonging
/// to the active profile, so exporting can never leak another profile's data.
class ExcelExportService {
  static const detailSheetName = '账单明细';
  static const categorySheetName = '分类汇总';
  static const monthlySheetName = '月度汇总';
  static const chartSheetName = '图表分析';

  static const _moneyFormat = '#,##0.00';
  static const _percentageFormat = '0.00%';
  static const _dateFormat = 'yyyy-mm-dd';
  static const _timeFormat = 'hh:mm:ss.000';

  static Uint8List createWorkbook({
    required Iterable<Record> records,
    required ExcelExportPeriod period,
    required Map<int, String> walletNames,
  }) {
    final selected =
        records.where((record) => period.includes(record.dateTime)).toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final summaries = _categorySummaries(selected);
    final monthly = _monthlySummaries(selected);
    final excel = Excel.createExcel();
    excel.rename('Sheet1', detailSheetName);

    _writeDetails(excel[detailSheetName], selected, walletNames);
    _writeCategorySummary(excel[categorySheetName], summaries);
    _writeMonthlySummary(excel[monthlySheetName], monthly);
    _writeAnalysis(excel[chartSheetName], summaries, monthly);

    final bytes = excel.save();
    if (bytes == null) {
      throw StateError('无法生成 Excel 文件');
    }
    return Uint8List.fromList(bytes);
  }

  static void _writeDetails(
    Sheet sheet,
    List<Record> records,
    Map<int, String> walletNames,
  ) {
    const headers = [
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
    ];
    _writeHeader(sheet, headers);
    sheet
      ..frozenRows = 1
      ..setColumnWidth(0, 14)
      ..setColumnWidth(1, 15)
      ..setColumnWidth(2, 10)
      ..setColumnWidth(3, 14)
      ..setColumnWidth(4, 24)
      ..setColumnWidth(5, 32)
      ..setColumnWidth(6, 14)
      ..setColumnWidth(7, 16)
      ..setColumnWidth(8, 16)
      ..setColumnWidth(9, 14);

    for (var row = 0; row < records.length; row++) {
      final record = records[row];
      final type = record.isTransfer
          ? '转账'
          : record.category?.categoryType == CategoryType.income
          ? '收入'
          : '支出';
      _set(
        sheet,
        0,
        row + 1,
        DateTimeCellValue(
          year: record.dateTime.year,
          month: record.dateTime.month,
          day: record.dateTime.day,
          hour: 0,
          minute: 0,
        ),
        style: _dateStyle,
      );
      _set(
        sheet,
        1,
        row + 1,
        TimeCellValue.fromTimeOfDateTime(record.dateTime),
        style: _timeStyle,
      );
      _set(sheet, 2, row + 1, TextCellValue(type));
      _set(sheet, 3, row + 1, TextCellValue(record.category?.name ?? '未分类'));
      // [title] deliberately remains its own column. It must never be used as
      // a category during export, especially for old CSV-imported records.
      _set(sheet, 4, row + 1, TextCellValue(record.title ?? ''));
      _set(sheet, 5, row + 1, TextCellValue(record.description ?? ''));
      _set(
        sheet,
        6,
        row + 1,
        DoubleCellValue((record.value ?? 0).abs()),
        style: _moneyStyle,
      );
      _set(
        sheet,
        7,
        row + 1,
        TextCellValue(walletNames[record.walletId] ?? ''),
      );
      _set(
        sheet,
        8,
        row + 1,
        TextCellValue(
          record.isTransfer ? (walletNames[record.transferWalletId] ?? '') : '',
        ),
      );
      _set(
        sheet,
        9,
        row + 1,
        TextCellValue(record.recurrencePatternId == null ? '否' : '是'),
      );
    }
    _setFilter(sheet, headers.length, records.length + 1);
  }

  static void _writeCategorySummary(
    Sheet sheet,
    List<_CategorySummary> summaries,
  ) {
    const headers = ['分类', '类型', '金额', '笔数', '占比'];
    _writeHeader(sheet, headers);
    sheet
      ..frozenRows = 1
      ..setColumnWidth(0, 18)
      ..setColumnWidth(1, 10)
      ..setColumnWidth(2, 16)
      ..setColumnWidth(3, 10)
      ..setColumnWidth(4, 12);

    for (var row = 0; row < summaries.length; row++) {
      final summary = summaries[row];
      _set(sheet, 0, row + 1, TextCellValue(summary.name));
      _set(
        sheet,
        1,
        row + 1,
        TextCellValue(summary.type == CategoryType.income ? '收入' : '支出'),
      );
      _set(
        sheet,
        2,
        row + 1,
        DoubleCellValue(summary.amount),
        style: _moneyStyle,
      );
      _set(sheet, 3, row + 1, IntCellValue(summary.count));
      _set(
        sheet,
        4,
        row + 1,
        DoubleCellValue(summary.percentage),
        style: _percentageStyle,
      );
    }
    _setFilter(sheet, headers.length, summaries.length + 1);
  }

  static void _writeMonthlySummary(
    Sheet sheet,
    List<_MonthlySummary> summaries,
  ) {
    const headers = ['月份', '收入', '支出', '结余'];
    _writeHeader(sheet, headers);
    sheet
      ..frozenRows = 1
      ..setColumnWidth(0, 14)
      ..setColumnWidth(1, 16)
      ..setColumnWidth(2, 16)
      ..setColumnWidth(3, 16);

    for (var row = 0; row < summaries.length; row++) {
      final summary = summaries[row];
      _set(sheet, 0, row + 1, TextCellValue(summary.month));
      _set(
        sheet,
        1,
        row + 1,
        DoubleCellValue(summary.income),
        style: _moneyStyle,
      );
      _set(
        sheet,
        2,
        row + 1,
        DoubleCellValue(summary.expense),
        style: _moneyStyle,
      );
      _set(
        sheet,
        3,
        row + 1,
        DoubleCellValue(summary.income - summary.expense),
        style: _moneyStyle,
      );
    }
    _setFilter(sheet, headers.length, summaries.length + 1);
  }

  static void _writeAnalysis(
    Sheet sheet,
    List<_CategorySummary> summaries,
    List<_MonthlySummary> monthly,
  ) {
    sheet
      ..setColumnWidth(0, 16)
      ..setColumnWidth(1, 16)
      ..setColumnWidth(2, 12)
      ..setColumnWidth(4, 16)
      ..setColumnWidth(5, 16)
      ..setColumnWidth(6, 16);

    const categoryHeaders = ['分类支出（前六及其他）', '金额', '占比'];
    _writeHeader(sheet, categoryHeaders);
    final expenses = summaries
        .where((summary) => summary.type == CategoryType.expense)
        .toList();
    final chartCategories = _topSixWithOther(expenses);
    for (var row = 0; row < chartCategories.length; row++) {
      final summary = chartCategories[row];
      _set(sheet, 0, row + 1, TextCellValue(summary.name));
      _set(
        sheet,
        1,
        row + 1,
        DoubleCellValue(summary.amount),
        style: _moneyStyle,
      );
      _set(
        sheet,
        2,
        row + 1,
        DoubleCellValue(summary.percentage),
        style: _percentageStyle,
      );
    }
    _setFilter(sheet, categoryHeaders.length, chartCategories.length + 1);

    const monthlyHeaders = ['月份', '收入', '支出'];
    const monthlyStartRow = 14;
    for (var column = 0; column < monthlyHeaders.length; column++) {
      _set(
        sheet,
        column,
        monthlyStartRow,
        TextCellValue(monthlyHeaders[column]),
        style: _headerStyle,
      );
    }
    for (var row = 0; row < monthly.length; row++) {
      final summary = monthly[row];
      _set(sheet, 0, monthlyStartRow + row + 1, TextCellValue(summary.month));
      _set(
        sheet,
        1,
        monthlyStartRow + row + 1,
        DoubleCellValue(summary.income),
        style: _moneyStyle,
      );
      _set(
        sheet,
        2,
        monthlyStartRow + row + 1,
        DoubleCellValue(summary.expense),
        style: _moneyStyle,
      );
    }

    if (chartCategories.isNotEmpty) {
      final endRow = chartCategories.length + 1;
      sheet.addChart(
        DoughnutChart(
          title: '分类支出分析',
          series: [
            ChartSeries(
              name: '支出',
              categoriesRange: '$chartSheetName!\$A\$2:\$A\$$endRow',
              valuesRange: '$chartSheetName!\$B\$2:\$B\$$endRow',
            ),
          ],
          anchor: ChartAnchor.at(column: 4, row: 0, width: 11, height: 12),
          showLegend: true,
          dataLabels: ChartDataLabels(
            categoryName: true,
            value: true,
            percentage: true,
          ),
        ),
      );
    }
    if (monthly.isNotEmpty) {
      final start = monthlyStartRow + 2;
      final end = monthlyStartRow + monthly.length + 1;
      sheet.addChart(
        ColumnChart(
          title: '月度收支',
          series: [
            ChartSeries(
              name: '收入',
              categoriesRange: '$chartSheetName!\$A\$$start:\$A\$$end',
              valuesRange: '$chartSheetName!\$B\$$start:\$B\$$end',
            ),
            ChartSeries(
              name: '支出',
              categoriesRange: '$chartSheetName!\$A\$$start:\$A\$$end',
              valuesRange: '$chartSheetName!\$C\$$start:\$C\$$end',
            ),
          ],
          anchor: ChartAnchor.at(
            column: 4,
            row: monthlyStartRow,
            width: 11,
            height: 13,
          ),
          showLegend: true,
        ),
      );
    }
  }

  static List<_CategorySummary> _categorySummaries(List<Record> records) {
    final totals = <String, _CategorySummary>{};
    final perTypeTotals = <CategoryType, double>{};
    for (final record in records) {
      if (record.isTransfer || record.category?.categoryType == null) continue;
      final type = record.category!.categoryType!;
      final name = record.category!.name ?? '未分类';
      final key = '${type.index}|$name';
      final amount = (record.value ?? 0).abs();
      final summary = totals.putIfAbsent(
        key,
        () => _CategorySummary(name: name, type: type),
      );
      summary.amount += amount;
      summary.count++;
      perTypeTotals[type] = (perTypeTotals[type] ?? 0) + amount;
    }
    final result = totals.values.toList();
    for (final summary in result) {
      final total = perTypeTotals[summary.type] ?? 0;
      summary.percentage = total == 0 ? 0 : summary.amount / total;
    }
    result.sort((a, b) {
      final typeCompare = a.type.index.compareTo(b.type.index);
      return typeCompare != 0 ? typeCompare : b.amount.compareTo(a.amount);
    });
    return result;
  }

  static List<_MonthlySummary> _monthlySummaries(List<Record> records) {
    final totals = <String, _MonthlySummary>{};
    for (final record in records) {
      if (record.isTransfer || record.category?.categoryType == null) continue;
      final date = record.dateTime;
      final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final summary = totals.putIfAbsent(month, () => _MonthlySummary(month));
      final amount = (record.value ?? 0).abs();
      if (record.category!.categoryType == CategoryType.income) {
        summary.income += amount;
      } else {
        summary.expense += amount;
      }
    }
    final result = totals.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));
    return result;
  }

  static List<_CategorySummary> _topSixWithOther(
    List<_CategorySummary> expenses,
  ) {
    if (expenses.length <= 6) return expenses;
    final top = expenses.take(6).toList();
    final otherAmount = expenses
        .skip(6)
        .fold<double>(0, (sum, summary) => sum + summary.amount);
    final total = expenses.fold<double>(
      0,
      (sum, summary) => sum + summary.amount,
    );
    top.add(
      _CategorySummary(
        name: '其他',
        type: CategoryType.expense,
        amount: otherAmount,
        percentage: total == 0 ? 0 : otherAmount / total,
      ),
    );
    return top;
  }

  static void _writeHeader(Sheet sheet, List<String> headers) {
    for (var column = 0; column < headers.length; column++) {
      _set(
        sheet,
        column,
        0,
        TextCellValue(headers[column]),
        style: _headerStyle,
      );
    }
  }

  static void _setFilter(Sheet sheet, int columns, int rows) {
    final lastColumn = _columnName(columns - 1);
    sheet.setAutoFilterByString('A1:$lastColumn$rows');
  }

  static void _set(
    Sheet sheet,
    int column,
    int row,
    CellValue value, {
    CellStyle? style,
  }) {
    sheet.updateCell(
      CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
      value,
      cellStyle: style,
    );
  }

  static String _columnName(int column) {
    var value = column + 1;
    var result = '';
    while (value > 0) {
      value--;
      result = String.fromCharCode(65 + (value % 26)) + result;
      value ~/= 26;
    }
    return result;
  }

  static final _headerStyle = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.fromHexString('FFF2CC'),
    horizontalAlign: HorizontalAlign.Center,
  );
  static final _moneyStyle = CellStyle(
    numberFormat: NumFormat.custom(formatCode: _moneyFormat),
    horizontalAlign: HorizontalAlign.Right,
  );
  static final _percentageStyle = CellStyle(
    numberFormat: NumFormat.custom(formatCode: _percentageFormat),
    horizontalAlign: HorizontalAlign.Right,
  );
  static final _dateStyle = CellStyle(
    numberFormat: NumFormat.custom(formatCode: _dateFormat),
  );
  static final _timeStyle = CellStyle(
    numberFormat: NumFormat.custom(formatCode: _timeFormat),
  );
}

class _CategorySummary {
  final String name;
  final CategoryType type;
  double amount;
  int count;
  double percentage;

  _CategorySummary({
    required this.name,
    required this.type,
    this.amount = 0,
    this.percentage = 0,
  }) : count = 0;
}

class _MonthlySummary {
  final String month;
  double income = 0;
  double expense = 0;

  _MonthlySummary(this.month);
}
