import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_shell.dart';
import '../../services/invoice_pdf_service.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  int _tabIndex = 0; // 0 = pending, 1 = paid
  bool _useFallback = false; // toggled by button only

  // Optional customer filter from query params
  String? _filterPhone;
  String? _filterName;

  @override
  void initState() {
    super.initState();
    final qp = Uri.base.queryParameters;
    final phone = qp['customerPhone']?.trim();
    final name = qp['customerName']?.trim();
    if (phone != null && phone.isNotEmpty) _filterPhone = phone;
    if (name != null && name.isNotEmpty) _filterName = name;
  }

  void _clearFilter() {
    setState(() {
      _filterPhone = null;
      _filterName = null;
    });
    // Also clean the URL so refresh doesn't reapply filter
    if (GoRouter.of(context).canPop()) {
      context.go('/invoices');
    } else {
      GoRouter.of(context).go('/invoices');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = (_filterPhone?.isNotEmpty ?? false) || (_filterName?.isNotEmpty ?? false);

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invoices',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 12),

          if (hasFilter)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filtered: '
                      '${_filterName ?? ''}'
                      '${(((_filterName ?? '').isNotEmpty) && ((_filterPhone ?? '').isNotEmpty)) ? " • " : ""}'
                      '${_filterPhone ?? ""}',
                      style: const TextStyle(color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _clearFilter,
                    icon: const Icon(Icons.clear, color: Colors.white70, size: 18),
                    label: const Text('Clear', style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              _TabChip(
                label: 'Pending',
                selected: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              const SizedBox(width: 8),
              _TabChip(
                label: 'Paid',
                selected: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
              const Spacer(),

              // ✅ Quick Shop removed from Invoices screen per request
              TextButton.icon(
                onPressed: () => setState(() {}),
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                label: const Text(
                  'Refresh',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _useFallback
                ? _FallbackInvoices(
                    tabIndex: _tabIndex,
                    filterPhone: _filterPhone,
                    filterName: _filterName,
                  )
                : _LiveInvoices(
                    tabIndex: _tabIndex,
                    onSwitchToFallback: () => setState(() => _useFallback = true),
                    filterPhone: _filterPhone,
                    filterName: _filterName,
                  ),
          ),
        ],
      ),
    );
  }
}

class _LiveInvoices extends StatelessWidget {
  final int tabIndex;
  final VoidCallback onSwitchToFallback;

  final String? filterPhone;
  final String? filterName;

  const _LiveInvoices({
    required this.tabIndex,
    required this.onSwitchToFallback,
    this.filterPhone,
    this.filterName,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _ErrorState(message: 'Not signed in.', onRetry: () {});
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, userSnap) {
        if (userSnap.hasError) {
          return _ErrorState(
            message: _safeErr('Failed to read user: ${userSnap.error}'),
            onRetry: () {},
          );
        }
        if (userSnap.connectionState == ConnectionState.waiting && !userSnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        final u = userSnap.data?.data() ?? const <String, dynamic>{};
        final role = (u['role'] as String?)?.toLowerCase() ?? '';
        final isSuper = role == 'superadmin';
        final branchIds = ((u['branchIds'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false);

        if (!isSuper && branchIds.length > 10) {
          return _GuidanceState(
            title: 'Too many branches to filter in one query',
            message:
                'Your account has ${branchIds.length} branches. whereIn supports up to 10. '
                'Use the fallback loader or reduce assignments.',
            actions: [
              _GuidanceButton(
                icon: Icons.swap_horiz,
                label: 'Use branch-by-branch fallback',
                onPressed: onSwitchToFallback,
              ),
            ],
          );
        }

        Query<Map<String, dynamic>> q = FirebaseFirestore.instance
            .collectionGroup('sessions')
            .where('status', isEqualTo: 'completed');

        if (!isSuper && branchIds.isNotEmpty && branchIds.length <= 10) {
          q = q.where('branchId', whereIn: branchIds);
        }

        // ---- Customer filter (if present) ----
        if (filterPhone != null && filterPhone!.isNotEmpty) {
          q = q.where('customerPhone', isEqualTo: filterPhone);
        } else if (filterName != null && filterName!.isNotEmpty) {
          q = q.where('customerName', isEqualTo: filterName);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: q.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              final msg = _safeErr(snap.error);
              if (msg.contains('failed-precondition') && msg.contains('create_exemption=')) {
                final url = _extractIndexUrl(msg);
                return _GuidanceState(
                  title: 'Firestore index required',
                  message:
                      'This collection-group query needs an index. '
                      'Create it using the link below, or use the fallback loader.',
                  actions: [
                    if (url != null)
                      _GuidanceButton(
                        icon: Icons.open_in_new,
                        label: 'Open Create Index link',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copy & open this URL:\n$url')),
                          );
                        },
                      ),
                    _GuidanceButton(
                      icon: Icons.swap_horiz,
                      label: 'Use branch-by-branch fallback',
                      onPressed: onSwitchToFallback,
                    ),
                  ],
                );
              }
              return _ErrorState(
                message: 'Failed to load invoices.\n$msg',
                onRetry: () {},
              );
            }

            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            }

            final docs = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final entries = _normalizeAndFilter(docs, tabIndex);
            if (entries.isEmpty) {
              return Center(
                child: Text(
                  tabIndex == 0 ? 'No pending invoices.' : 'No paid invoices.',
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            }
            return _InvoiceList(entries: entries, tabIndex: tabIndex);
          },
        );
      },
    );
  }
}

class _FallbackInvoices extends StatelessWidget {
  final int tabIndex;
  final String? filterPhone;
  final String? filterName;

  const _FallbackInvoices({
    required this.tabIndex,
    this.filterPhone,
    this.filterName,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _loadAllBranchInvoices(filterPhone: filterPhone, filterName: filterName),
      builder: (context, snap) {
        if (snap.hasError) {
          return _ErrorState(
            message: _safeErr('Failed to load (fallback): ${snap.error}'),
            onRetry: () {},
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        final docs = snap.data ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final entries = _normalizeAndFilter(docs, tabIndex);
        if (entries.isEmpty) {
          return Center(
            child: Text(
              tabIndex == 0 ? 'No pending invoices.' : 'No paid invoices.',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        return _InvoiceList(entries: entries, tabIndex: tabIndex);
      },
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadAllBranchInvoices({
    String? filterPhone,
    String? filterName,
  }) async {
    final bSnap = await FirebaseFirestore.instance.collection('branches').get();
    final branchIds = bSnap.docs.map((d) => d.id).toList();

    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (final bid in branchIds) {
      futures.add(
        FirebaseFirestore.instance
            .collection('branches')
            .doc(bid)
            .collection('sessions')
            .where('status', isEqualTo: 'completed')
            .get(),
      );
    }

    final results = await Future.wait(futures);
    final all = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final rs in results) {
      for (final d in rs.docs) {
        // Apply customer filter in-memory for fallback
        final m = d.data();
        final phone = (m['customerPhone'] ?? '').toString();
        final name = (m['customerName'] ?? '').toString();
        final phoneOk = (filterPhone == null || filterPhone!.isEmpty) ? true : phone == filterPhone;
        final nameOk = (filterName == null || filterName!.isEmpty) ? true : name == filterName;
        if (phoneOk && nameOk) {
          all.add(d);
        }
      }
    }
    return all;
  }
}

// ---------- Shared list rendering ----------

class _InvoiceList extends StatelessWidget {
  final List<MapEntry<QueryDocumentSnapshot<Map<String, dynamic>>, Map<String, dynamic>>> entries;
  final int tabIndex;

  const _InvoiceList({required this.entries, required this.tabIndex});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final doc = entry.key;
        final data = entry.value;

        final customerName = (data['customerName'] as String?)?.trim();
        final cust = (customerName == null || customerName.isEmpty) ? 'Guest' : customerName;

        final amount = (data['billAmount'] as double?) ?? 0.0;
        final closedAt = data['closedAt'] as DateTime?;
        final playedMinutes = (data['playedMinutes'] is num) ? (data['playedMinutes'] as num).toInt() : null;
        final invoiceNumber = data['invoiceNumber'];
        final branchId = (data['branchId'] as String?) ?? '';
        final payments = (data['payments'] as List<Map<String, dynamic>>?) ?? const [];
        final totalPaid = payments.fold<double>(0, (prev, e) {
          final amt = (e['amount'] is num) ? (e['amount'] as num).toDouble() : 0.0;
          return prev + amt;
        });
        final remaining = (amount - totalPaid);
        final remainingClamped = remaining < 0 ? 0.0 : remaining;

        final itemsOnly = data['itemsOnly'] == true;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          cust,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        if (itemsOnly)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.2),
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Items-only',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    if (invoiceNumber != null)
                      Text(
                        invoiceNumber.toString(),
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    Text(
                      closedAt != null ? closedAt.toLocal().toString() : '',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                    if (playedMinutes != null)
                      Text(
                        'Played: $playedMinutes minutes',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    if (payments.isNotEmpty)
                      Text(
                        'Paid: ₹${totalPaid.toStringAsFixed(2)} • Remaining: ₹${remainingClamped.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Text(
                '₹${amount.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: branchId.isEmpty
                    ? null
                    : () async {
                        await InvoicePdfService().generateAndPrint(
                          branchId: branchId,
                          sessionId: doc.id,
                        );
                      },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF'),
              ),
              const SizedBox(width: 8),
              if (tabIndex == 0)
                OutlinedButton(
                  onPressed: () => _showRecordPaymentDialog(context, doc, amount),
                  child: const Text('Record Payment'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRecordPaymentDialog(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    num billAmount,
  ) async {
    final data = doc.data();
    final existingPayments = (data['payments'] as List<dynamic>?) ?? <dynamic>[];
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecordPaymentDialog(
        sessionDoc: doc,
        sessionData: data,
        billAmount: billAmount.toDouble(),
        existingPayments: existingPayments.whereType<Map<String, dynamic>>().toList(growable: false),
      ),
    );
  }
}

// ---------- Small UI helpers ----------

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final safe = _safeErr(message);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              safe,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
              label: const Text('Retry', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceState extends StatelessWidget {
  final String title;
  final String message;
  final List<Widget> actions;

  const _GuidanceState({
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _GuidanceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// RECORD PAYMENT DIALOG (unchanged)
// ---------------------------------------------------------------------------

class _RecordPaymentDialog extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> sessionDoc;
  final Map<String, dynamic> sessionData;
  final double billAmount;
  final List<Map<String, dynamic>> existingPayments;

  const _RecordPaymentDialog({
    required this.sessionDoc,
    required this.sessionData,
    required this.billAmount,
    required this.existingPayments,
  });

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _PaymentRow {
  String mode;
  final TextEditingController amountCtrl;
  _PaymentRow({required this.mode, required this.amountCtrl});
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  final List<_PaymentRow> _rows = [];
  bool _saving = false;
  String? _error;

  double get _existingTotal => widget.existingPayments.fold<double>(0, (prev, e) {
        final v = (e['amount'] as num?) ?? 0;
        return prev + v.toDouble();
      });

  double get _remaining => widget.billAmount - _existingTotal;

  @override
  void initState() {
    super.initState();
    final initialAmount = _remaining > 0 ? _remaining : 0;
    _rows.add(
      _PaymentRow(
        mode: 'cash',
        amountCtrl: TextEditingController(text: initialAmount.toStringAsFixed(0)),
      ),
    );
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.amountCtrl.dispose();
    }
    super.dispose();
  }

  double _sumNewPayments() {
    double total = 0;
    for (final r in _rows) {
      final amt = double.tryParse(r.amountCtrl.text.trim()) ?? 0;
      total += amt;
    }
    return total;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final newPayments = <Map<String, dynamic>>[];
      for (final r in _rows) {
        final amt = double.tryParse(r.amountCtrl.text.trim()) ?? 0;
        if (amt <= 0) continue;
        newPayments.add({'mode': r.mode, 'amount': amt});
      }

      if (_remaining <= 0 && newPayments.isEmpty) {
        await widget.sessionDoc.reference.update({'paymentStatus': 'paid'});
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice marked as paid')),
        );
        return;
      }

      if (newPayments.isEmpty) {
        setState(() {
          _error = 'Enter at least one valid payment amount.';
          _saving = false;
        });
        return;
      }

      final finalTotal = _existingTotal + _sumNewPayments();
      if ((finalTotal - widget.billAmount).abs() > 0.05) {
        setState(() {
          _error =
              'Payment split must equal ₹${widget.billAmount.toStringAsFixed(2)}.\nCurrently: ₹${finalTotal.toStringAsFixed(2)}.';
          _saving = false;
        });
        return;
      }

      final allPayments = [...widget.existingPayments, ...newPayments];
      await widget.sessionDoc.reference.update({
        'payments': allPayments,
        'paymentStatus': 'paid',
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice marked as paid')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _safeErr('Failed to record payment: $e');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.sessionData;
    final customerName = d['customerName']?.toString() ?? 'Guest';
    final customerPhone = d['customerPhone']?.toString() ?? '';
    final branchName = d['branchName']?.toString() ?? '';
    final seatLabel = d['seatLabel']?.toString() ?? '';
    final startTime = d['startTime'] as Timestamp?;
    final closedAt = d['closedAt'] as Timestamp?;
    final playedMinutes = (d['playedMinutes'] as num?)?.toInt();
    final subtotal = (d['subtotal'] as num?)?.toDouble() ?? widget.billAmount;
    final discount = (d['discount'] as num?)?.toDouble() ?? 0;
    final taxPercent = (d['taxPercent'] as num?)?.toDouble() ?? 0;
    final taxAmount = (d['taxAmount'] as num?)?.toDouble() ?? 0;

    return AlertDialog(
      backgroundColor: const Color(0xFF1F2937),
      contentPadding: const EdgeInsets.all(16),
      title: const Text('Invoice & Payment', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Customer & Session',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 8),
                _KeyValueRow(
                  label: 'Customer',
                  value: customerPhone.isNotEmpty ? '$customerName • $customerPhone' : customerName,
                ),
                _KeyValueRow(
                  label: 'Branch & Seat',
                  value: [
                    if (branchName.isNotEmpty) branchName,
                    if (seatLabel.isNotEmpty) 'Seat $seatLabel',
                  ].join(' • '),
                ),
                _KeyValueRow(
                  label: 'Timing',
                  value: [
                    if (startTime != null) 'Start: ${startTime.toDate().toLocal()}',
                    if (closedAt != null) 'End: ${closedAt.toDate().toLocal()}',
                  ].join('\n'),
                ),
                if (playedMinutes != null) _KeyValueRow(label: 'Played', value: '$playedMinutes minutes'),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 12),
                const Text(
                  'Billing Breakdown',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 8),
                _KeyValueRow(label: 'Subtotal', value: '₹${subtotal.toStringAsFixed(2)}'),
                _KeyValueRow(
                  label: 'Discount',
                  value: discount == 0 ? '₹0.00' : '- ₹${discount.toStringAsFixed(2)}',
                ),
                _KeyValueRow(
                  label: 'Tax',
                  value: '${taxPercent.toStringAsFixed(1)}% • ₹${taxAmount.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 4),
                _KeyValueRow(
                  label: 'Total Payable',
                  value: '₹${widget.billAmount.toStringAsFixed(2)}',
                  highlight: true,
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 12),
                if (widget.existingPayments.isNotEmpty) ...[
                  const Text(
                    'Existing Payments',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: widget.existingPayments.map((p) {
                      final mode = p['mode']?.toString().toUpperCase() ?? 'N/A';
                      final amount = (p['amount'] as num?)?.toDouble() ?? 0;
                      return Row(
                        children: [
                          Expanded(child: Text(mode, style: const TextStyle(color: Colors.white70))),
                          Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70)),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                  _KeyValueRow(label: 'Total Already Paid', value: '₹${_existingTotal.toStringAsFixed(2)}'),
                  _KeyValueRow(
                    label: 'Remaining to Collect',
                    value: '₹${_remaining <= 0 ? '0.00' : _remaining.toStringAsFixed(2)}',
                    highlight: true,
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Record Payment (split by mode)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Column(
                  children: [
                    for (int i = 0; i < _rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                value: _rows[i].mode,
                                dropdownColor: const Color(0xFF111827),
                                decoration: const InputDecoration(
                                  labelText: 'Mode',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                                ),
                                style: const TextStyle(color: Colors.white),
                                items: const [
                                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                  DropdownMenuItem(value: 'card', child: Text('Card')),
                                  DropdownMenuItem(value: 'upi', child: Text('UPI')),
                                  DropdownMenuItem(value: 'other', child: Text('Other')),
                                ],
                                onChanged: (v) => _rows[i].mode = v ?? 'cash',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _rows[i].amountCtrl,
                                style: const TextStyle(color: Colors.white),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Amount',
                                  labelStyle: TextStyle(color: Colors.white70),
                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_rows.length > 1)
                              IconButton(
                                tooltip: 'Remove row',
                                onPressed: () {
                                  setState(() {
                                    final r = _rows.removeAt(i);
                                    r.amountCtrl.dispose();
                                  });
                                },
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                              ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _rows.add(_PaymentRow(mode: 'cash', amountCtrl: TextEditingController()));
                          });
                        },
                        icon: const Icon(Icons.add, color: Colors.white, size: 18),
                        label: const Text('Add another payment', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _KeyValueRow(label: 'New Payments Total', value: '₹${_sumNewPayments().toStringAsFixed(2)}'),
                _KeyValueRow(
                  label: 'Final Total (existing + new)',
                  value: '₹${(_existingTotal + _sumNewPayments()).toStringAsFixed(2)}',
                  highlight: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Mark as Paid'),
        ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade300,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: highlight ? Colors.white : Colors.white70,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                fontSize: highlight ? 13 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Shared helpers (defined ONCE) ----------

List<MapEntry<QueryDocumentSnapshot<Map<String, dynamic>>, Map<String, dynamic>>> _normalizeAndFilter(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  int tabIndex,
) {
  final normalized = <MapEntry<QueryDocumentSnapshot<Map<String, dynamic>>, Map<String, dynamic>>>[];

  for (final d in docs) {
    try {
      final m = d.data();
      if (m['status'] != 'completed') continue;

      final paymentStatus = (m['paymentStatus'] as String?)?.trim().toLowerCase();
      final safeStatus =
          (paymentStatus == 'paid' || paymentStatus == 'pending') ? paymentStatus! : 'pending';

      final closedAtTs = m['closedAt'];
      final closedAt = (closedAtTs is Timestamp) ? closedAtTs.toDate() : null;

      final billAmount = (m['billAmount'] is num) ? (m['billAmount'] as num).toDouble() : 0.0;

      final rawPayments = m['payments'];
      final payments = <Map<String, dynamic>>[];
      if (rawPayments is List) {
        for (final p in rawPayments) {
          if (p is Map<String, dynamic>) {
            final mode = (p['mode'] as String?) ?? 'other';
            final amt = (p['amount'] is num) ? (p['amount'] as num).toDouble() : 0.0;
            payments.add({'mode': mode, 'amount': amt});
          }
        }
      }

      final entry = MapEntry<QueryDocumentSnapshot<Map<String, dynamic>>, Map<String, dynamic>>(
        d,
        {
          ...m,
          'paymentStatus': safeStatus,
          'closedAt': closedAt,
          'billAmount': billAmount,
          'payments': payments,
        },
      );
      normalized.add(entry);
    } catch (_) {}
  }

  final filtered = normalized.where((e) {
    final ps = (e.value['paymentStatus'] as String?) ?? 'pending';
    return tabIndex == 0 ? ps == 'pending' : ps == 'paid';
  }).toList()
    ..sort((a, b) {
      final aDt = a.value['closedAt'] as DateTime?;
      final bDt = b.value['closedAt'] as DateTime?;
      if (aDt == null && bDt == null) return 0;
      if (aDt == null) return 1;
      if (bDt == null) return -1;
      return bDt.compareTo(aDt);
    });

  return filtered;
}

String _safeErr(Object? e) {
  try {
    return e?.toString() ?? 'Unknown error';
  } catch (_) {
    return 'Unknown error';
  }
}

String? _extractIndexUrl(String msg) {
  final start = msg.indexOf('https://console.firebase.google.com');
  if (start == -1) return null;
  final space = msg.indexOf(' ', start);
  final end = space == -1 ? msg.length : space;
  return msg.substring(start, end).trim();
}
