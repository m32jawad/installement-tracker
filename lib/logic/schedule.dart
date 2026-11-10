// Pure business logic for installment plans: schedule generation, payment
// allocation and status computation. No Flutter / database imports here so
// it can be unit-tested directly (see test/schedule_test.dart).

enum Frequency { monthly, weekly, biweekly, custom }

Frequency frequencyFromName(String? name) => Frequency.values.firstWhere(
      (f) => f.name == name,
      orElse: () => Frequency.monthly,
    );

String frequencyLabel(Frequency f, [int customDays = 30]) {
  switch (f) {
    case Frequency.monthly:
      return 'Monthly';
    case Frequency.weekly:
      return 'Weekly';
    case Frequency.biweekly:
      return 'Bi-weekly';
    case Frequency.custom:
      return 'Every $customDays days';
  }
}

enum InstStatus { pending, paid, partial, skipped, overdue }

String instStatusLabel(InstStatus s) {
  switch (s) {
    case InstStatus.pending:
      return 'Pending';
    case InstStatus.paid:
      return 'Paid';
    case InstStatus.partial:
      return 'Partially Paid';
    case InstStatus.skipped:
      return 'Skipped';
    case InstStatus.overdue:
      return 'Overdue';
  }
}

enum SaleStatus { active, overdue, completed, cancelled }

String saleStatusLabel(SaleStatus s) {
  switch (s) {
    case SaleStatus.active:
      return 'Active';
    case SaleStatus.overdue:
      return 'Overdue';
    case SaleStatus.completed:
      return 'Completed';
    case SaleStatus.cancelled:
      return 'Cancelled';
  }
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Adds [months] to [d], clamping the day to the end of the target month
/// (31 Jan + 1 month = 28/29 Feb).
DateTime addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final day = d.day > daysInMonth(y, m) ? daysInMonth(y, m) : d.day;
  return DateTime(y, m, day);
}

DateTime dueDateFor(DateTime firstDue, int index, Frequency f, int customDays) {
  switch (f) {
    case Frequency.monthly:
      return addMonths(firstDue, index);
    case Frequency.weekly:
      return dateOnly(firstDue).add(Duration(days: 7 * index));
    case Frequency.biweekly:
      return dateOnly(firstDue).add(Duration(days: 14 * index));
    case Frequency.custom:
      return dateOnly(firstDue)
          .add(Duration(days: (customDays < 1 ? 1 : customDays) * index));
  }
}

class PlanError implements Exception {
  final String message;
  PlanError(this.message);
  @override
  String toString() => message;
}

class ScheduledInstallment {
  final int number;
  final DateTime dueDate;
  final int amount;
  const ScheduledInstallment(this.number, this.dueDate, this.amount);
}

/// Number of installments needed to pay [remaining] at [installmentAmount] each.
int autoInstallmentCount(int remaining, int installmentAmount) {
  if (remaining <= 0 || installmentAmount <= 0) return 0;
  return (remaining + installmentAmount - 1) ~/ installmentAmount;
}

/// Builds the installment schedule for a sale.
///
/// remaining = total - advance. If [count] is null it is derived from the
/// installment amount; every installment is [installmentAmount] except the
/// last, which absorbs the difference so the schedule always sums exactly to
/// the remaining amount.
List<ScheduledInstallment> generateSchedule({
  required int total,
  required int advance,
  required int installmentAmount,
  int? count,
  required DateTime firstDue,
  Frequency frequency = Frequency.monthly,
  int customDays = 30,
}) {
  if (total <= 0) throw PlanError('Total price must be more than 0');
  if (advance < 0) throw PlanError('Advance cannot be negative');
  if (advance > total) throw PlanError('Advance cannot be more than total');
  final remaining = total - advance;
  if (remaining == 0) return const [];
  if (installmentAmount <= 0) {
    throw PlanError('Installment amount must be more than 0');
  }
  final n = count ?? autoInstallmentCount(remaining, installmentAmount);
  if (n <= 0) throw PlanError('Number of installments must be at least 1');
  if (n > 600) throw PlanError('Too many installments ($n)');
  final last = remaining - installmentAmount * (n - 1);
  if (last <= 0) {
    throw PlanError(
        '$n installments of $installmentAmount is more than the remaining $remaining. '
        'Use ${autoInstallmentCount(remaining, installmentAmount)} installments or a smaller amount.');
  }
  return List.generate(n, (i) {
    final amt = i == n - 1 ? last : installmentAmount;
    return ScheduledInstallment(
        i + 1, dueDateFor(firstDue, i, frequency, customDays), amt);
  });
}

// ---------------------------------------------------------------------------
// Payment allocation
// ---------------------------------------------------------------------------

class InstallmentInput {
  final int id;
  final int number;
  final DateTime dueDate;
  final int amount;
  final bool skipped;
  const InstallmentInput({
    required this.id,
    required this.number,
    required this.dueDate,
    required this.amount,
    this.skipped = false,
  });
}

class PaymentInput {
  final int id;

  /// Installment the seller chose. Null = "apply to oldest unpaid".
  final int? installmentId;
  final int amount;
  final DateTime date;
  final String method;

  /// Advance / down payment recorded at sale time; not allocated to installments.
  final bool isAdvance;

  /// When the payment is bigger than the chosen installment: true = carry the
  /// extra to the next installments, false = keep it as credit on the sale.
  final bool applyExtraToNext;
  const PaymentInput({
    required this.id,
    this.installmentId,
    required this.amount,
    required this.date,
    this.method = 'Cash',
    this.isAdvance = false,
    this.applyExtraToNext = true,
  });
}

class InstallmentState {
  final InstallmentInput input;
  int paid = 0;
  DateTime? paidDate;
  String? method;
  late InstStatus status;

  InstallmentState(this.input);

  int get id => input.id;
  int get number => input.number;
  DateTime get dueDate => input.dueDate;
  int get amount => input.amount;
  bool get skipped => input.skipped;
  int get remaining => amount - paid > 0 ? amount - paid : 0;
  bool get isOpen => remaining > 0;

  /// Days past due (0 when not late or already paid).
  int daysLate(DateTime today) {
    if (!isOpen) return 0;
    final d = dateOnly(today).difference(dateOnly(dueDate)).inDays;
    return d > 0 ? d : 0;
  }

  /// Paid after the due date (used for "most late" payer reports).
  bool get paidLate =>
      !isOpen && paidDate != null && dateOnly(paidDate!).isAfter(dateOnly(dueDate));
}

class SaleComputation {
  final int total;
  final List<InstallmentState> installments;
  final int advancePaid;
  final int installmentPaid;

  /// Extra money kept "as advance" (not applied to any installment).
  final int credit;
  final SaleStatus status;
  final DateTime today;

  SaleComputation({
    required this.today,
    required this.total,
    required this.installments,
    required this.advancePaid,
    required this.installmentPaid,
    required this.credit,
    required this.status,
  });

  int get totalPaid => advancePaid + installmentPaid + credit;
  int get remaining => total - totalPaid > 0 ? total - totalPaid : 0;
  double get progress => total <= 0 ? 0 : (totalPaid / total).clamp(0.0, 1.0);

  /// First open installment that is not skipped.
  InstallmentState? get nextDue {
    for (final i in installments) {
      if (i.isOpen && !i.skipped) return i;
    }
    return null;
  }

  /// Open, not-skipped installments whose due date has passed.
  List<InstallmentState> get overdue => installments
      .where((i) => !i.skipped && i.daysLate(today) > 0)
      .toList();

  bool get hasSkippedOpen => installments.any((i) => i.skipped && i.isOpen);
}

/// Allocates payments to installments and computes every derived number for a
/// sale. Installment paid amounts / statuses are never stored as truth: they
/// are recomputed from payments, so editing or deleting a payment updates
/// every total immediately (spec scenario 4).
SaleComputation computeSale({
  required int total,
  required List<InstallmentInput> installments,
  required List<PaymentInput> payments,
  required DateTime today,
  bool cancelled = false,
}) {
  final states = [...installments]..sort((a, b) => a.number.compareTo(b.number));
  final list = states.map(InstallmentState.new).toList();
  final byId = {for (final s in list) s.id: s};

  int advance = 0;
  int allocated = 0;
  int credit = 0;

  final ordered = [...payments]..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

  void give(InstallmentState s, int amt, PaymentInput p) {
    s.paid += amt;
    s.paidDate = p.date;
    s.method = p.method;
    allocated += amt;
  }

  for (final p in ordered) {
    if (p.isAdvance) {
      advance += p.amount;
      continue;
    }
    var left = p.amount;
    final target = p.installmentId == null ? null : byId[p.installmentId];
    if (target != null && target.isOpen) {
      final take = left < target.remaining ? left : target.remaining;
      give(target, take, p);
      left -= take;
    }
    if (left > 0 && (target == null || p.applyExtraToNext)) {
      // Later installments first, then any earlier ones still open.
      final startIdx = target == null ? 0 : list.indexOf(target) + 1;
      final order = [...list.sublist(startIdx), ...list.sublist(0, startIdx)];
      for (final s in order) {
        if (left <= 0) break;
        if (s.skipped || !s.isOpen || identical(s, target)) continue;
        final take = left < s.remaining ? left : s.remaining;
        give(s, take, p);
        left -= take;
      }
    }
    if (left > 0) credit += left;
  }

  final t = dateOnly(today);
  for (final s in list) {
    if (!s.isOpen) {
      s.status = InstStatus.paid;
    } else if (s.skipped) {
      s.status = InstStatus.skipped;
    } else if (s.paid > 0) {
      s.status = InstStatus.partial;
    } else if (dateOnly(s.dueDate).isBefore(t)) {
      s.status = InstStatus.overdue;
    } else {
      s.status = InstStatus.pending;
    }
  }

  final paidTotal = advance + allocated + credit;
  SaleStatus status;
  if (cancelled) {
    status = SaleStatus.cancelled;
  } else if (paidTotal >= total) {
    status = SaleStatus.completed;
  } else if (list.any((s) => s.isOpen && !s.skipped && s.daysLate(t) > 0)) {
    status = SaleStatus.overdue;
  } else {
    status = SaleStatus.active;
  }

  return SaleComputation(
    today: t,
    total: total,
    installments: list,
    advancePaid: advance,
    installmentPaid: allocated,
    credit: credit,
    status: status,
  );
}
