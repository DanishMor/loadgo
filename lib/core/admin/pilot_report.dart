/// Daily or weekly pilot numbers for a copy-paste message (MASTER-6 Task 5).
/// Numbers only: no names, phones or amounts of a person.
class PilotReport {
  final bool weekly;
  final DateTime from;
  final DateTime to;
  final int signups;
  final int loads;
  final int bookings;
  final int delivered;
  final int cancelled;
  final int sos;
  final int tickets;

  const PilotReport({
    required this.weekly,
    required this.from,
    required this.to,
    this.signups = 0,
    this.loads = 0,
    this.bookings = 0,
    this.delivered = 0,
    this.cancelled = 0,
    this.sos = 0,
    this.tickets = 0,
  });

  /// How many bookings are read to split them by status.
  static const bookingSample = 1000;

  /// Start of the period that ends at [now]: today's midnight, or midnight
  /// six days earlier (seven calendar days including today).
  static DateTime periodStart(DateTime now, {required bool weekly}) {
    final midnight = DateTime(now.year, now.month, now.day);
    return weekly ? DateTime(midnight.year, midnight.month, midnight.day - 6) : midnight;
  }

  /// Bookings out of loads, as a whole percent (null with no loads; never above 100).
  int? get fillPercent => loads == 0 ? null : (bookings * 100 ~/ loads).clamp(0, 100);

  /// Delivered out of finished (delivered + cancelled) bookings, whole percent.
  int? get deliveredPercent {
    final done = delivered + cancelled;
    return done == 0 ? null : delivered * 100 ~/ done;
  }

  static String _d(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  /// The message. [label] gives the text for a key (title, signups, loads,
  /// bookings, delivered, cancelled, fill, deliveredRate, sos, tickets).
  String text(String Function(String key) label) {
    final days = weekly ? '${_d(from)} - ${_d(to)}' : _d(from);
    final lines = <String>[
      '${label(weekly ? 'weeklyTitle' : 'dailyTitle')} ($days)',
      '${label('signups')}: $signups',
      '${label('loads')}: $loads',
      '${label('bookings')}: $bookings',
      '${label('delivered')}: $delivered',
      '${label('cancelled')}: $cancelled',
      if (fillPercent != null) '${label('fill')}: $fillPercent%',
      if (deliveredPercent != null) '${label('deliveredRate')}: $deliveredPercent%',
      '${label('sos')}: $sos',
      '${label('tickets')}: $tickets',
    ];
    return lines.join('\n');
  }
}
