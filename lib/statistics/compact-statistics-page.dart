import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:piggybank/helpers/records-utility-functions.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/statistics/category-analysis.dart';

/// Compact, phone-first statistics. It reads records only and never mutates
/// bills, categories, or database state.
class CompactStatisticsPage extends StatefulWidget {
  const CompactStatisticsPage({
    super.key,
    required this.records,
    required this.walletCurrencyMap,
  });

  final List<Record?> records;
  final Map<int, String?> walletCurrencyMap;

  @override
  State<CompactStatisticsPage> createState() => _CompactStatisticsPageState();
}

enum _StatisticsPeriod { week, month, year }

enum _CategoryAnalysisMode { ranking, pie }

class _CompactStatisticsPageState extends State<CompactStatisticsPage> {
  static const _yellow = Color(0xFFFFD21F);

  late _StatisticsPeriod _period;
  late CategoryType _categoryType;
  late DateTime _selectedStart;
  late DateTime _visibleEnd;
  late List<Record?> _records;
  late _CategoryAnalysisMode _analysisMode;

  @override
  void initState() {
    super.initState();
    _period = _StatisticsPeriod.week;
    _categoryType = CategoryType.expense;
    _records = widget.records;
    _selectedStart = _normalizeStart(DateTime.now());
    _visibleEnd = _selectedStart;
    _analysisMode = _CategoryAnalysisMode.ranking;
  }

  @override
  void didUpdateWidget(covariant CompactStatisticsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) _records = widget.records;
  }

  DateTime _normalizeStart(DateTime value) {
    switch (_period) {
      case _StatisticsPeriod.week:
        return DateTime(
          value.year,
          value.month,
          value.day,
        ).subtract(Duration(days: value.weekday - DateTime.monday));
      case _StatisticsPeriod.month:
        return DateTime(value.year, value.month);
      case _StatisticsPeriod.year:
        return DateTime(value.year);
    }
  }

  DateTime _addPeriod(DateTime date, int amount) {
    switch (_period) {
      case _StatisticsPeriod.week:
        return date.add(Duration(days: 7 * amount));
      case _StatisticsPeriod.month:
        return DateTime(date.year, date.month + amount);
      case _StatisticsPeriod.year:
        return DateTime(date.year + amount);
    }
  }

  DateTime _endExclusive(DateTime start) {
    switch (_period) {
      case _StatisticsPeriod.week:
        return start.add(const Duration(days: 7));
      case _StatisticsPeriod.month:
        return DateTime(start.year, start.month + 1);
      case _StatisticsPeriod.year:
        return DateTime(start.year + 1);
    }
  }

  List<DateTime> get _periodOptions =>
      List.generate(5, (index) => _addPeriod(_visibleEnd, index - 4));

  List<Record?> get _typedRecords => _records.where((record) {
    return record != null &&
        !record.isTransfer &&
        record.category?.categoryType == _categoryType;
  }).toList();

  List<Record?> get _selectedRecords {
    final end = _endExclusive(_selectedStart);
    return _typedRecords.where((record) {
      final date = record!.dateTime;
      return !date.isBefore(_selectedStart) && date.isBefore(end);
    }).toList();
  }

  double _total(Iterable<Record?> records) => computeConvertedTotal(
    records,
    widget.walletCurrencyMap,
    isAbsValue: true,
  ).total;

  List<_TrendPoint> get _trend {
    switch (_period) {
      case _StatisticsPeriod.week:
        return List.generate(7, (index) {
          final start = _selectedStart.add(Duration(days: index));
          return _TrendPoint(start, _total(_recordsForRange(start, 1)));
        });
      case _StatisticsPeriod.month:
        final count = DateTime(
          _selectedStart.year,
          _selectedStart.month + 1,
          0,
        ).day;
        return List.generate(count, (index) {
          final start = DateTime(
            _selectedStart.year,
            _selectedStart.month,
            index + 1,
          );
          return _TrendPoint(start, _total(_recordsForRange(start, 1)));
        });
      case _StatisticsPeriod.year:
        return List.generate(12, (index) {
          final start = DateTime(_selectedStart.year, index + 1);
          final end = DateTime(_selectedStart.year, index + 2);
          final matches = _typedRecords.where((record) {
            final date = record!.dateTime;
            return !date.isBefore(start) && date.isBefore(end);
          });
          return _TrendPoint(start, _total(matches));
        });
    }
  }

  Iterable<Record?> _recordsForRange(DateTime start, int days) {
    final end = start.add(Duration(days: days));
    return _typedRecords.where((record) {
      final date = record!.dateTime;
      return !date.isBefore(start) && date.isBefore(end);
    });
  }

  int get _averageDivisor {
    final now = DateTime.now();
    final currentStart = _normalizeStart(now);
    if (_selectedStart != currentStart) {
      switch (_period) {
        case _StatisticsPeriod.week:
          return 7;
        case _StatisticsPeriod.month:
          return DateTime(_selectedStart.year, _selectedStart.month + 1, 0).day;
        case _StatisticsPeriod.year:
          return 12;
      }
    }
    switch (_period) {
      case _StatisticsPeriod.week:
        return now.difference(_selectedStart).inDays.clamp(1, 7);
      case _StatisticsPeriod.month:
        return now.day;
      case _StatisticsPeriod.year:
        return now.month;
    }
  }

  List<CategoryAnalysisEntry> get _ranking => aggregateCategoryAnalysis(
    _selectedRecords,
    widget.walletCurrencyMap,
    categoryType: _categoryType,
  );

  String _formatTotal(double value) => NumberFormat('#,##0.00').format(value);
  String _formatAmount(double value) => NumberFormat('#,##0.##').format(value);

  String _periodOptionLabel(DateTime start) {
    final now = _normalizeStart(DateTime.now());
    if (start == now) {
      switch (_period) {
        case _StatisticsPeriod.week:
          return '本周';
        case _StatisticsPeriod.month:
          return '本月';
        case _StatisticsPeriod.year:
          return '今年';
      }
    }
    switch (_period) {
      case _StatisticsPeriod.week:
        return '${_isoWeekNumber(start)}周';
      case _StatisticsPeriod.month:
        return '${start.month.toString().padLeft(2, '0')}月';
      case _StatisticsPeriod.year:
        return '${start.year}年';
    }
  }

  int _isoWeekNumber(DateTime value) {
    final thursday = value.add(Duration(days: 4 - value.weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final firstMonday = firstThursday.subtract(
      Duration(days: firstThursday.weekday - DateTime.monday),
    );
    return thursday.difference(firstMonday).inDays ~/ 7 + 1;
  }

  void _changePeriod(_StatisticsPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _selectedStart = _normalizeStart(DateTime.now());
      _visibleEnd = _selectedStart;
    });
  }

  void _movePeriodStrip(int amount) {
    final now = _normalizeStart(DateTime.now());
    final candidate = _addPeriod(_visibleEnd, amount);
    if (candidate.isAfter(now)) return;
    setState(() {
      _visibleEnd = candidate;
      if (!_periodOptions.any((item) => item == _selectedStart)) {
        _selectedStart = candidate;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _total(_selectedRecords);
    final trend = _trend;
    final ranking = _ranking;
    final pieEntries = buildPieAnalysisEntries(ranking);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildYellowHeader(context),
            _buildPeriodStrip(context),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity.abs() >= 120) {
                    _movePeriodStrip(velocity < 0 ? 1 : -1);
                  }
                },
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _StatisticsTotals(
                        total: _formatTotal(total),
                        average: _formatAmount(total / _averageDivisor),
                        label: _categoryType == CategoryType.expense
                            ? '总支出'
                            : '总收入',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 1, 10, 4),
                      child: _TrendChart(
                        points: trend,
                        period: _period,
                        maxText: _formatAmount(
                          trend.fold<double>(
                            0,
                            (maxValue, point) =>
                                math.max(maxValue, point.value),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    _buildAnalysisHeader(context),
                    if (ranking.isEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(18, 24, 18, 42),
                        child: Text(
                          '当前周期暂无账单',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: .58),
                            fontSize: 14,
                          ),
                        ),
                      )
                    else if (_analysisMode == _CategoryAnalysisMode.ranking)
                      ...ranking.map(
                        (item) => _RankingRow(
                          item: item,
                          total: total,
                          max: ranking.first.amount,
                          formatAmount: _formatAmount,
                        ),
                      )
                    else
                      _PieAnalysis(
                        entries: pieEntries,
                        total: total,
                        typeLabel: _categoryType == CategoryType.expense
                            ? '支出'
                            : '收入',
                        formatAmount: _formatAmount,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYellowHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? colorScheme.surfaceContainer : _yellow;
    final ink = isDark ? colorScheme.onSurface : const Color(0xFF282828);
    final selectedSegmentColor = isDark ? const Color(0xFF151515) : ink;
    final selectedSegmentTextColor = isDark ? colorScheme.primary : headerColor;
    return Container(
      color: headerColor,
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 8),
      child: Column(
        children: [
          PopupMenuButton<CategoryType>(
            initialValue: _categoryType,
            onSelected: (value) => setState(() => _categoryType = value),
            color: colorScheme.surfaceContainer,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 100, minHeight: 26),
            itemBuilder: (_) => const [
              PopupMenuItem(value: CategoryType.expense, child: Text('支出')),
              PopupMenuItem(value: CategoryType.income, child: Text('收入')),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _categoryType == CategoryType.expense ? '支出' : '收入',
                  style: TextStyle(
                    color: ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.arrow_drop_down, color: ink, size: 22),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: ink, width: 1.2),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              children: _StatisticsPeriod.values.map((period) {
                final selected = _period == period;
                final label = switch (period) {
                  _StatisticsPeriod.week => '周',
                  _StatisticsPeriod.month => '月',
                  _StatisticsPeriod.year => '年',
                };
                return Expanded(
                  child: InkWell(
                    onTap: () => _changePeriod(period),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? selectedSegmentColor
                            : Colors.transparent,
                        border: period == _StatisticsPeriod.year
                            ? null
                            : Border(right: BorderSide(color: ink, width: 1)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected ? selectedSegmentTextColor : ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _categoryType == CategoryType.expense ? '支出排行榜' : '收入排行榜',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _AnalysisModeToggle(
          selected: _analysisMode,
          onChanged: (value) => setState(() => _analysisMode = value),
        ),
      ],
    ),
  );

  Widget _buildPeriodStrip(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: _periodOptions.map((option) {
          final selected = option == _selectedStart;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedStart = option),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    _periodOptionLabel(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withValues(alpha: .45),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  if (selected)
                    Positioned(
                      bottom: 0,
                      child: SizedBox(
                        height: 3,
                        width: 30,
                        child: ColoredBox(color: colorScheme.onSurface),
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatisticsTotals extends StatelessWidget {
  const _StatisticsTotals({
    required this.total,
    required this.average,
    required this.label,
  });

  final String total;
  final String average;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：$total',
          style: TextStyle(
            color: onSurface.withValues(alpha: .68),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '平均值：$average',
          style: TextStyle(
            color: onSurface.withValues(alpha: .58),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _TrendPoint {
  const _TrendPoint(this.date, this.value);

  final DateTime date;
  final double value;
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.points,
    required this.period,
    required this.maxText,
  });

  final List<_TrendPoint> points;
  final _StatisticsPeriod period;
  final String maxText;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 166,
    child: CustomPaint(
      painter: _TrendChartPainter(
        points: points,
        period: period,
        maxText: maxText,
        lineColor: Theme.of(context).colorScheme.onSurface
            .withValues(alpha: .58),
        guideColor: Theme.of(context).colorScheme.outlineVariant,
        emptyPointColor: Theme.of(context).colorScheme.surface,
        textColor: Theme.of(context).colorScheme.onSurface
            .withValues(alpha: .58),
      ),
      size: Size.infinite,
    ),
  );
}

class _TrendChartPainter extends CustomPainter {
  const _TrendChartPainter({
    required this.points,
    required this.period,
    required this.maxText,
    required this.lineColor,
    required this.guideColor,
    required this.emptyPointColor,
    required this.textColor,
  });

  final List<_TrendPoint> points;
  final _StatisticsPeriod period;
  final String maxText;
  final Color lineColor;
  final Color guideColor;
  final Color emptyPointColor;
  final Color textColor;
  static const _yellow = Color(0xFFFFD21F);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 12.0;
    const right = 8.0;
    const top = 25.0;
    const bottom = 23.0;
    final chartWidth = size.width - left - right;
    final baseline = size.height - bottom;
    final chartHeight = baseline - top;
    final maximum = points.fold<double>(
      0,
      (current, point) => math.max(current, point.value),
    );
    final visualMaximum = maximum == 0 ? 1.0 : maximum;
    final pointsOnCanvas = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final x = left + chartWidth * index / math.max(1, points.length - 1);
      final y = baseline - (points[index].value / visualMaximum) * chartHeight;
      pointsOnCanvas.add(Offset(x, y));
    }

    final gridPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.55)
      ..strokeWidth = 0.7;
    canvas.drawLine(
      Offset(left, top),
      Offset(size.width - right, top),
      gridPaint,
    );
    _drawDashedLine(
      canvas,
      Offset(left, top + chartHeight / 2),
      Offset(size.width - right, top + chartHeight / 2),
      Paint()
        ..color = guideColor
        ..strokeWidth = 0.8,
    );
    canvas.drawLine(
      Offset(left, baseline),
      Offset(size.width - right, baseline),
      gridPaint,
    );

    final path = Path()
      ..moveTo(pointsOnCanvas.first.dx, pointsOnCanvas.first.dy);
    for (final point in pointsOnCanvas.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85,
    );
    for (var index = 0; index < pointsOnCanvas.length; index++) {
      final value = points[index].value;
      canvas.drawCircle(
        pointsOnCanvas[index],
        3.5,
        Paint()
          ..color = value > 0 ? _yellow : emptyPointColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        pointsOnCanvas[index],
        3.5,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.85,
      );
    }
    _paintText(
      canvas,
      maxText,
      Offset(size.width - right, 2),
      TextStyle(color: textColor, fontSize: 12),
      alignRight: true,
    );
    for (final index in _labelIndexes()) {
      _paintText(
        canvas,
        _labelFor(points[index].date),
        Offset(pointsOnCanvas[index].dx, baseline + 6),
        TextStyle(color: textColor, fontSize: 10),
        centered: true,
      );
    }
  }

  Iterable<int> _labelIndexes() {
    if (period == _StatisticsPeriod.week || period == _StatisticsPeriod.year) {
      return List<int>.generate(points.length, (index) => index);
    }
    final candidates = <int>{
      0,
      4,
      9,
      13,
      17,
      21,
      26,
      points.length - 1,
    }.where((index) => index >= 0 && index < points.length).toList()..sort();
    return candidates;
  }

  String _labelFor(DateTime date) {
    switch (period) {
      case _StatisticsPeriod.week:
        return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      case _StatisticsPeriod.month:
        return date.day.toString().padLeft(2, '0');
      case _StatisticsPeriod.year:
        return '${date.month}月';
    }
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 8.0;
    const gap = 7.0;
    var x = from.dx;
    while (x < to.dx) {
      canvas.drawLine(
        Offset(x, from.dy),
        Offset(math.min(x + dash, to.dx), to.dy),
        paint,
      );
      x += dash + gap;
    }
  }

  void _paintText(
    Canvas canvas,
    String value,
    Offset offset,
    TextStyle style, {
    bool centered = false,
    bool alignRight = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    var dx = offset.dx;
    if (centered) dx -= painter.width / 2;
    if (alignRight) dx -= painter.width;
    painter.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.period != period ||
      oldDelegate.maxText != maxText ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.guideColor != guideColor ||
      oldDelegate.emptyPointColor != emptyPointColor ||
      oldDelegate.textColor != textColor;
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.item,
    required this.total,
    required this.max,
    required this.formatAmount,
  });

  final CategoryAnalysisEntry item;
  final double total;
  final double max;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : item.amount / total * 100;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.category?.icon ?? Icons.category_outlined,
              color: colorScheme.onSurface.withValues(alpha: .75),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${percent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: .62),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 4,
                      width: math.max(
                        10.0,
                        constraints.maxWidth * item.amount / max,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD21F),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              formatAmount(item.amount),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: .82),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisModeToggle extends StatelessWidget {
  const _AnalysisModeToggle({required this.selected, required this.onChanged});

  final _CategoryAnalysisMode selected;
  final ValueChanged<_CategoryAnalysisMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outline, width: .8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, '排行榜', _CategoryAnalysisMode.ranking),
          _segment(context, '饼图', _CategoryAnalysisMode.pie),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    String label,
    _CategoryAnalysisMode mode,
  ) {
    final isSelected = selected == mode;
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('statistics-analysis-${mode.name}'),
      onTap: () => onChanged(mode),
      child: Container(
        width: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.surfaceContainerHighest
              : Colors.transparent,
          border: mode == _CategoryAnalysisMode.ranking
              ? Border(right: BorderSide(color: colorScheme.outline, width: .8))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: .75),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PieAnalysis extends StatelessWidget {
  const _PieAnalysis({
    required this.entries,
    required this.total,
    required this.typeLabel,
    required this.formatAmount,
  });

  final List<CategoryAnalysisEntry> entries;
  final double total;
  final String typeLabel;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
      child: Column(
        children: [
          SizedBox(
            height: 188,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 172,
                  height: 172,
                  child: CustomPaint(painter: _DonutChartPainter(entries)),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      typeLabel,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: .58),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatAmount(total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ...entries.map(
            (entry) => _PieLegendRow(
              entry: entry,
              total: total,
              formatAmount: formatAmount,
            ),
          ),
        ],
      ),
    );
  }
}

class _PieLegendRow extends StatelessWidget {
  const _PieLegendRow({
    required this.entry,
    required this.total,
    required this.formatAmount,
  });

  final CategoryAnalysisEntry entry;
  final double total;
  final String Function(double) formatAmount;

  @override
  Widget build(BuildContext context) {
    final percent = total == 0 ? 0.0 : entry.amount / total * 100;
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: categoryAnalysisColor(entry),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(
              '${percent.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: .58),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: Text(
              formatAmount(entry.amount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter(this.entries);

  final List<CategoryAnalysisEntry> entries;

  @override
  void paint(Canvas canvas, Size size) {
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.amount);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 17;
    const strokeWidth = 30.0;
    var startAngle = -math.pi / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (final entry in entries) {
      final sweepAngle = entry.amount / total * math.pi * 2;
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = categoryAnalysisColor(entry)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) =>
      oldDelegate.entries != entries;
}
