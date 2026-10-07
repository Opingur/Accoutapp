import 'package:flutter/material.dart';
import 'package:piggybank/helpers/records-utility-functions.dart';
import 'package:piggybank/models/category-type.dart';
import 'package:piggybank/models/record.dart';
import 'package:piggybank/services/service-config.dart';

import 'home_compact_metrics.dart';

/// The fixed, image-free header used by the records home screen.
class CompactHomeHeader extends StatelessWidget {
  const CompactHomeHeader({
    super.key,
    required this.records,
    required this.walletCurrencyMap,
    required this.month,
    required this.onMonthTap,
    required this.onProfileTap,
  });

  final List<Record?> records;
  final Map<int, String?> walletCurrencyMap;
  final DateTime month;
  final VoidCallback onMonthTap;
  final VoidCallback onProfileTap;

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

  String _total(Iterable<Record?> value) =>
      formatRecordsTotalResult(computeConvertedTotal(value, walletCurrencyMap));

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF202020);
    const yellow = Color(0xFFFFD21F);
    return ValueListenableBuilder<bool>(
      valueListenable: ServiceConfig.privacyModeHiddenNotifier,
      builder: (context, hidden, _) {
        const amountStyle = TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        );
        return SizedBox(
          height: HomeCompactMetrics.homeHeaderHeight,
          child: Container(
            color: yellow,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: '个人资料',
                        child: InkResponse(
                          onTap: onProfileTap,
                          radius: 22,
                          child: const CircleAvatar(
                            radius: 16,
                            backgroundColor: Color(0x33FFFFFF),
                            child: Icon(
                              Icons.person_outline,
                              color: ink,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Oinkoin',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 32),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 64,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 30,
                        child: _MonthColumn(month: month, onTap: onMonthTap),
                      ),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        indent: 6,
                        endIndent: 6,
                        color: Color(0x66584412),
                      ),
                      _TotalColumn(
                        label: '收入',
                        value: _total(_income),
                        hidden: hidden,
                        style: amountStyle,
                      ),
                      _TotalColumn(
                        label: '支出',
                        value: _total(_expenses),
                        hidden: hidden,
                        style: amountStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MonthColumn extends StatelessWidget {
  const _MonthColumn({required this.month, required this.onTap});

  final DateTime month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${month.year}年',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6C5926),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${month.month}月',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF202020),
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Color(0xFF202020),
                    size: 24,
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

class _TotalColumn extends StatelessWidget {
  const _TotalColumn({
    required this.label,
    required this.value,
    required this.hidden,
    required this.style,
  });

  final String label;
  final String value;
  final bool hidden;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: 35,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF6C5926),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: hidden
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: obscuredAmountTextWidget(style),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
          ),
        ),
      ],
    ),
  );
}
