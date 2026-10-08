/// Visual metrics shared by the compact records home experience.
///
/// These values deliberately affect presentation only.  Keeping them here
/// makes the month overview, record rows, and bottom navigation scale as one
/// composition without changing records, filtering, or navigation behavior.
abstract final class HomeCompactMetrics {
  static const double homeTitle = 18;
  static const double monthYear = 11;
  static const double monthValue = 20;
  static const double overviewLabel = 11;
  static const double overviewAmount = 18;
  static const double overviewSecondaryLabel = 10;
  static const double overviewSecondaryAmount = 14;

  static const double dayHeader = 12;
  static const double dayTotal = 10;
  static const double recordTitle = 14;
  static const double recordAmount = 14;
  static const double recordSecondary = 11;
  static const double recordIconCircle = 34;
  static const double recordIcon = 17;

  static const double bottomBarHeight = 64;
  static const double bottomIcon = 23;
  static const double bottomLabel = 10;
  static const double primaryActionSize = 54;
  static const double primaryActionIcon = 29;
  static const double recordRowHeight = 56;
  static const double homeHeaderHeight = 128;
}
