import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class QuickShopDialog extends StatefulWidget {
  final String branchId;
  const QuickShopDialog({super.key, required this.branchId});

  @override
  State<QuickShopDialog> createState() => _QuickShopDialogState();
}

class _QuickShopDialogState extends State<QuickShopDialog> {
  // Customer (optional)
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // Items (inventory bound)
  final List<_QSInvItem> _items = [_QSInvItem.initial()];

  // Money
  double _taxPercent = 0;
  double _discount = 0;

  // Payment status
  String _paymentStatus = 'paid'; // 'paid'|'pending'

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _normalizePhone(String raw) {
    var s = raw.replaceAll(RegExp(r'\D'), '');
    if (s.startsWith('91') && s.length == 12) s = s.substring(2);
    if (s.startsWith('0') && s.length == 11) s = s.substring(1);
    return s;
  }

  double get _ordersSubtotal {
    double s = 0;
    for (final it in _items) {
      if (!it.isValid) continue;
      s += it.qty * it.price;
    }
    return s;
  }

  double get _taxAmount {
    final base = (_ordersSubtotal - _discount);
    final safe = base < 0 ? 0.0 : base;
    return safe * (_taxPercent / 100.0);
  }

  double get _billAmount => (_ordersSubtotal - _discount).clamp(0, double.infinity) + _taxAmount;

  bool get _canSubmit {
    // Bill-only requires at least one valid item
    return _items.any((it) => it.isValid);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F2937),
      title: const Text('Quick Shop', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 720,
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Customer
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Customer name (optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _phoneCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Customer phone (optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _itemsHeader(),
              const SizedBox(height: 8),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (int i = 0; i < _items.length; i++) _itemRow(i),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _items.add(_QSInvItem.initial())),
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text('Add item', style: TextStyle(color: Colors.white)),
                        ),
                      ),

                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _numField(
                              label: 'Discount (₹)',
                              value: _discount,
                              onChanged: (v) => setState(
                                () => _discount = (double.tryParse(v) ?? 0).clamp(0, 1e12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _numField(
                              label: 'Tax (%)',
                              value: _taxPercent,
                              onChanged: (v) => setState(
                                () => _taxPercent = (double.tryParse(v) ?? 0).clamp(0, 100),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _sumLine('Items Subtotal', _ordersSubtotal),
                                  _sumLine('Discount', -_discount),
                                  _sumLine('Tax', _taxAmount),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Total', style: TextStyle(color: Colors.white60)),
                                Text(
                                  '₹ ${_billAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Payment:', style: TextStyle(color: Colors.white70)),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _paymentStatus,
                            dropdownColor: const Color(0xFF111827),
                            style: const TextStyle(color: Colors.white),
                            items: const [
                              DropdownMenuItem(value: 'paid', child: Text('Paid')),
                              DropdownMenuItem(value: 'pending', child: Text('Pending')),
                            ],
                            onChanged: (v) => setState(() => _paymentStatus = v ?? 'paid'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _saving || !_canSubmit ? null : _submit,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('Generate Bill'),
        ),
      ],
    );
  }

  Widget _itemsHeader() {
    return Row(
      children: const [
        Expanded(flex: 7, child: Text('Item', style: TextStyle(color: Colors.white54))),
        Expanded(flex: 3, child: Text('Qty', style: TextStyle(color: Colors.white54))),
        Expanded(flex: 3, child: Text('Price', style: TextStyle(color: Colors.white54))),
        SizedBox(width: 40),
      ],
    );
  }

  Widget _itemRow(int i) {
    final it = _items[i];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Item picker
          Expanded(
            flex: 7,
            child: InkWell(
              onTap: () => _openInventoryPicker(i),
              child: InputDecorator(
                decoration: const InputDecoration(
                  hintText: 'Select item from inventory',
                  hintStyle: TextStyle(color: Colors.white38),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
                child: Text(
                  it.name.isEmpty ? 'Tap to select' : it.name,
                  style: TextStyle(color: it.name.isEmpty ? Colors.white38 : Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Qty stepper
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: it.qty <= 1 ? null : () => setState(() => it.qty -= 1),
                    icon: const Icon(Icons.remove, color: Colors.white70),
                    splashRadius: 18,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(it.qty.toString(), style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => it.qty += 1),
                    icon: const Icon(Icons.add, color: Colors.white70),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Price (read only)
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                it.price <= 0 ? '₹ 0.00' : '₹ ${it.price.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 8),

          IconButton(
            onPressed: _items.length == 1 ? null : () => setState(() => _items.removeAt(i)),
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _numField({
    required String label,
    required double value,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
      ),
    );
  }

  Widget _sumLine(String label, double amt) {
    final sign = amt < 0 ? '-' : '+';
    final abs = amt.abs();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white60))),
          Text('$sign ₹ ${abs.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Future<void> _openInventoryPicker(int index) async {
    final selected = await showDialog<InventoryItemModel>(
      context: context,
      builder: (_) => _InventoryPickerDialog(branchId: widget.branchId),
    );

    if (selected != null) {
      setState(() {
        _items[index]
          ..itemId = selected.id
          ..name = selected.name
          ..price = (selected.price as num).toDouble()
          ..maxStock = (selected.stockQty as num).toInt()
          ..qty = 1;
      });
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final fs = FirebaseFirestore.instance;
      final now = DateTime.now();

      // branch name (for invoices/filters)
      String? branchName;
      final bDoc = await fs.collection('branches').doc(widget.branchId).get();
      if (bDoc.exists) {
        branchName = (bDoc.data()?['name'] ?? '').toString();
      }

      // current user audit
      final currentUser = FirebaseAuth.instance.currentUser;
      String? createdByName;
      if (currentUser != null) {
        final userDoc = await fs.collection('users').doc(currentUser.uid).get();
        if (userDoc.exists) {
          createdByName = (userDoc.data()?['name'] as String?) ?? currentUser.email;
        }
      }

      final sessionsCol = fs.collection('branches').doc(widget.branchId).collection('sessions');

      // compute money safely
      final rawSubtotal = (_ordersSubtotal - _discount);
      final safeSubtotal = rawSubtotal < 0 ? 0.0 : rawSubtotal;
      final taxAmt = safeSubtotal * (_taxPercent / 100.0);
      final totalPayable = safeSubtotal + taxAmt;

      // items array
      final items = _items.where((e) => e.isValid).map((e) {
        return {
          'itemId': e.itemId,
          'name': e.name,
          'qty': e.qty,
          'price': e.price,
          'total': e.qty * e.price,
        };
      }).toList();

      // payments
      final List<Map<String, dynamic>> payments =
          (_paymentStatus == 'paid') ? [{'mode': 'cash', 'amount': totalPayable}] : const [];

      final docRef = sessionsCol.doc();
      final invoiceNo = _genInvoiceNumber(docRef.id, now);

      await fs.runTransaction((tx) async {
        // validate & stage inventory updates
        final stagedUpdates = <DocumentReference<Map<String, dynamic>>, num>{};

        for (final it in _items.where((e) => e.isValid)) {
          final invRef = fs.collection('branches').doc(widget.branchId).collection('inventory').doc(it.itemId);

          final snap = await tx.get(invRef);
          if (!snap.exists) {
            throw Exception('Inventory item not found: ${it.name}');
          }
          final data = snap.data()!;
          final stock = InventoryItemModel._numOrZero(data['stockQty']);
          if (it.qty > stock) {
            throw Exception('Not enough stock for "${it.name}". Available: $stock, asked: ${it.qty}.');
          }
          stagedUpdates[invRef] = stock - it.qty;
        }

        // write session doc
        tx.set(docRef, {
          'status': 'completed',
          'paymentStatus': _paymentStatus,
          'payments': payments,

          'itemsOnly': true,
          'hiddenFromBookings': true,
          'quickShop': true,
          'quickShopMode': 'billOnly',

          'branchId': widget.branchId,
          'branchName': branchName,

          'seatId': null,
          'seatLabel': '—',
          'pax': 1,

          'startTime': Timestamp.fromDate(now),
          'closedAt': Timestamp.fromDate(now),
          'playedMinutes': 0,

          // money
          'ordersSubtotal': _ordersSubtotal,
          'subtotal': safeSubtotal,
          'discount': _discount,
          'taxPercent': _taxPercent,
          'taxAmount': taxAmt,
          'billAmount': totalPayable,

          // invoice/meta
          'invoiceNumber': invoiceNo,

          // customer optional
          if (_nameCtrl.text.trim().isNotEmpty) 'customerName': _nameCtrl.text.trim(),
          if (_phoneCtrl.text.trim().isNotEmpty) 'customerPhone': _normalizePhone(_phoneCtrl.text),

          // helpful for PDF/dialog fallback
          'orders': items,

          // audit
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (currentUser != null) 'createdBy': currentUser.uid,
          if (createdByName != null) 'createdByName': createdByName,
          if (currentUser != null) 'closedBy': currentUser.uid,
          if (createdByName != null) 'closedByName': createdByName,
        });

        // apply inventory decrements
        stagedUpdates.forEach((ref, newStock) {
          tx.update(ref, {'stockQty': newStock});
        });
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  String _genInvoiceNumber(String docId, DateTime now) {
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'INV-$y$m$d-$h$min$s';
  }
}

// ==== Inventory Picker dialog ====

class _InventoryPickerDialog extends StatefulWidget {
  final String branchId;
  const _InventoryPickerDialog({required this.branchId});

  @override
  State<_InventoryPickerDialog> createState() => _InventoryPickerDialogState();
}

class _InventoryPickerDialogState extends State<_InventoryPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F2937),
      title: const Text('Select item', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Search',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .doc(widget.branchId)
                    .collection('inventory')
                    .where('active', isEqualTo: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load inventory: ${snap.error}',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  final all = snap.data!.docs
                      .map((d) => InventoryItemModel.fromMap(d.id, d.data()))
                      .toList();
                  final filtered =
                      _q.isEmpty ? all : all.where((i) => i.name.toLowerCase().contains(_q)).toList();
                  if (filtered.isEmpty) {
                    return const Center(child: Text('No items', style: TextStyle(color: Colors.white70)));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                    itemBuilder: (_, i) {
                      final it = filtered[i];
                      final stock = (it.stockQty as num).toInt();
                      final price = (it.price as num).toDouble();
                      return ListTile(
                        onTap: () => Navigator.of(context).pop(it),
                        title: Text(it.name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          '₹ ${price.toStringAsFixed(2)} • Stock: $stock',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}

// ==== QS Item ====

class _QSInvItem {
  String itemId;
  String name;
  int qty;
  double price;
  int maxStock;

  _QSInvItem({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.price,
    required this.maxStock,
  });

  factory _QSInvItem.initial() => _QSInvItem(
        itemId: '',
        name: '',
        qty: 1,
        price: 0,
        maxStock: 0,
      );

  bool get isValid => itemId.isNotEmpty && name.isNotEmpty && qty > 0 && price >= 0;
}

// ---------------------------------------------------------------------------
// InventoryItemModel (kept here so this file is self-contained)
// ---------------------------------------------------------------------------

class InventoryItemModel {
  final String id;
  final String name;
  final num price;
  final num stockQty;
  final String? sku;
  final bool active;

  final num reorderThreshold;

  InventoryItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.stockQty,
    this.sku,
    required this.active,
    this.reorderThreshold = 0,
  });

  static num _numOrZero(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  factory InventoryItemModel.fromMap(String id, Map<String, dynamic> data) {
    return InventoryItemModel(
      id: id,
      name: data['name'] ?? '',
      price: _numOrZero(data['price']),
      stockQty: _numOrZero(data['stockQty']),
      sku: data['sku'],
      active: data['active'] ?? true,
      reorderThreshold: _numOrZero(data['reorderThreshold']),
    );
  }
}
