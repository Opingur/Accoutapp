import 'package:flutter/material.dart';
import 'package:piggybank/helpers/records-utility-functions.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/services/service-config.dart';

import 'home_compact_metrics.dart';

/// A compact, month-first overview for the records home screen.
///
/// It only renders totals from the supplied records; fetching, filtering and
/// currency conversion continue to be owned by [TabRecordsController].
class MonthOverviewHeader extends StatelessWidget {
  const MonthOverviewHeader({
    super.key,
    required this.records,
    required this.walletCurrencyMap,
    required this.month,
    required this.onMonthTap,
    required this.onPrevious,
    required this.onNext,
    required this.canNavigate,
  });

  final List<Record?> records;
  final Map<int, String?> walletCurrencyMap;
  final DateTime month;
  final VoidCallback onMonthTap;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final bool canNavigate;

  Iterable<Record?> get _expenses => records.where(
    (record) =>
        record != null &&
        !record.isTransfer &&
        record.category?.categoryType == CategoryType.expense,
  );

  Iterable<Record?> get _income => records.where(
    (record) =>
        record != null &&
        !record.isTransfer &&
        record.category?.categoryType == CategoryType.income,
  );

  Iterable<Record?> get _balance =>
      records.where((record) => record != null && !record.isTransfer);

  String _total(Iterable<Record?> value, {bool signed = false}) {
    return formatRecordsTotalResult(
      computeConvertedTotal(value, walletCurrencyMap, isAbsValue: !signed),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF202020);
    const yellow = Color(0xFFFFD21F);

    return ValueListenableBuilder<bool>(
      valueListenable: ServiceConfig.privacyModeHiddenNotifier,
      builder: (context, hidden, _) {
        final expenseStyle = const TextStyle(
          color: ink,
          fontSize: HomeCompactMetrics.overviewAmount,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
        );
        return Container(
          color: yellow,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: canNavigate ? onPrevious : null,
                    icon: const Icon(Icons.chevron_left_rounded, color: ink),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: onMonthTap,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${month.year}年',
                              style: const TextStyle(
                                color: ink,
                                fontSize: HomeCompactMetrics.monthYear,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${month.month}月',
                              style: const TextStyle(
                                color: ink,
                                fontSize: HomeCompactMetrics.monthValue,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down_rounded,
                              color: ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: canNavigate ? onNext : null,
                    icon: const Icon(Icons.chevron_right_rounded, color: ink),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '本月支出',
                style: TextStyle(
                  color: ink.withValues(alpha: 0.72),
                  fontSize: HomeCompactMetrics.overviewLabel,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              hidden
                  ? obscuredAmountTextWidget(expenseStyle)
                  : Text(_total(_expenses), style: expenseStyle),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SmallTotal(
                      label: '本月收入',
                      value: _total(_income),
                      hidden: hidden,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: ink.withValues(alpha: 0.22),
                  ),
                  Expanded(
                    child: _SmallTotal(
                      label: '本月结余',
                      value: _total(_balance, signed: true),
                      hidden: hidden,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SmallTotal extends StatelessWidget {
  const _SmallTotal({
    required this.label,
    required this.value,
    required this.hidden,
  });

  final String label;
  final String value;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Color(0xFF202020),
      fontSize: HomeCompactMetrics.overviewSecondaryAmount,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF57513B),
              fontSize: HomeCompactMetrics.overviewSecondaryLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          hidden ? obscuredAmountTextWidget(style) : Text(value, style: style),
        ],
      ),
    );
  }
}
