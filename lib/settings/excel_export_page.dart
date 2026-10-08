import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:piggybank/services/excel_export_service.dart';
import 'package:piggybank/services/platform-file-service.dart';
import 'package:piggybank/services/profile-service.dart';
import 'package:piggybank/services/service-config.dart';

/// Data-management flow for exporting the active profile as an Excel report.
class ExcelExportPage extends StatefulWidget {
  const ExcelExportPage({super.key});

  @override
  State<ExcelExportPage> createState() => _ExcelExportPageState();
}

class _ExcelExportPageState extends State<ExcelExportPage> {
  ExcelExportRange _range = ExcelExportRange.currentMonth;
  DateTimeRange? _customRange;
  bool _exporting = false;

  ExcelExportPeriod _periodForSelection(DateTime now) => switch (_range) {
    ExcelExportRange.currentMonth => ExcelExportPeriod.currentMonth(now),
    ExcelExportRange.currentYear => ExcelExportPeriod.currentYear(now),
    ExcelExportRange.custom when _customRange != null =>
      ExcelExportPeriod.custom(_customRange!.start, _customRange!.end),
    ExcelExportRange.custom => ExcelExportPeriod.currentMonth(now),
    ExcelExportRange.all => const ExcelExportPeriod.all(),
  };

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      initialDateRange:
          _customRange ??
          DateTimeRange(start: DateTime(now.year, now.month), end: now),
      helpText: '选择导出日期范围',
      saveText: '确定',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _range = ExcelExportRange.custom;
      _customRange = selected;
    });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final profileId = ProfileService.instance.activeProfileId;
      final recordsFuture = ServiceConfig.database.getAllRecords(
        profileId: profileId,
      );
      final walletsFuture = ServiceConfig.database.getAllWallets(
        profileId: profileId,
      );
      final records = await recordsFuture;
      final wallets = await walletsFuture;
      final period = _periodForSelection(DateTime.now());
      final bytes = ExcelExportService.createWorkbook(
        records: records.whereType(),
        period: period,
        walletNames: {
          for (final wallet in wallets)
            if (wallet.id != null) wallet.id!: wallet.name,
        },
      );
      final cacheDirectory = await getTemporaryDirectory();
      final name = 'Oinkoin账单分析_${period.fileNamePart}.xlsx';
      final file = File('${cacheDirectory.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      final saved = await PlatformFileService.saveFileWithSystemPicker(
        filePath: file.path,
        suggestedName: name,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(saved ? 'Excel 已保存' : '已取消保存')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出 Excel 失败：$error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _labelFor(ExcelExportRange value) => switch (value) {
    ExcelExportRange.currentMonth => '本月',
    ExcelExportRange.currentYear => '本年',
    ExcelExportRange.custom =>
      _customRange == null
          ? '自定义日期'
          : '${_customRange!.start.year}/${_customRange!.start.month}/${_customRange!.start.day} - ${_customRange!.end.year}/${_customRange!.end.month}/${_customRange!.end.day}',
    ExcelExportRange.all => '全部账单',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导出 Excel')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '选择导出范围',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        RadioGroup<ExcelExportRange>(
          groupValue: _range,
          onChanged: (selection) {
            if (selection == ExcelExportRange.custom) {
              _pickCustomRange();
            } else if (selection != null) {
              setState(() => _range = selection);
            }
          },
          child: Column(
            children: [
              for (final value in ExcelExportRange.values)
                RadioListTile<ExcelExportRange>(
                  value: value,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_labelFor(value)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('工作簿包含：账单明细、分类汇总、月度汇总和图表分析。'),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _exporting ? null : _export,
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.table_view_outlined),
          label: Text(_exporting ? '正在生成…' : '导出 Excel'),
        ),
      ],
    ),
  );
}
