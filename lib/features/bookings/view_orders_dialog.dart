import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ViewOrdersDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;

  const ViewOrdersDialog({
    super.key,
    required this.branchId,
    required this.sessionId,
  });

  @override
  State<ViewOrdersDialog> createState() => _ViewOrdersDialogState();
}

class _ViewOrdersDialogState extends State<ViewOrdersDialog> {
  bool _busy = false;

  Future<void> _removeOrder(String orderId, Map<String, dynamic> orderData) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text('Remove Order?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove ${orderData['itemName']} (${orderData['qty']} pcs)?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _busy = true);

    try {
      final fs = FirebaseFirestore.instance;
      final orderRef = fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('sessions')
          .doc(widget.sessionId)
          .collection('orders')
          .doc(orderId);

      final invRef = fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .doc(orderData['itemId']);

      await fs.runTransaction((tx) async {
        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) {
          throw Exception('Inventory item not found');
        }

        final invData = invSnap.data() as Map<String, dynamic>;
        final currentStock = _asNum(invData['stockQty']).toInt();
        final qty = _asNum(orderData['qty']).toInt();

        tx.delete(orderRef);

        tx.update(invRef, {
          'stockQty': currentStock + qty,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final uid = FirebaseAuth.instance.currentUser?.uid;
        tx.set(invRef.collection('logs').doc(), {
          'type': 'return',
          'qty': qty,
          'at': FieldValue.serverTimestamp(),
          'note': 'Removed from session ${widget.sessionId}',
          if (uid != null) 'userId': uid,
        });
      });

      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }

  Future<void> _updateQuantity(String orderId, Map<String, dynamic> orderData, int delta) async {
    setState(() => _busy = true);

    try {
      final fs = FirebaseFirestore.instance;
      final orderRef = fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('sessions')
          .doc(widget.sessionId)
          .collection('orders')
          .doc(orderId);

      final invRef = fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('inventory')
          .doc(orderData['itemId']);

      await fs.runTransaction((tx) async {
        final invSnap = await tx.get(invRef);
        if (!invSnap.exists) {
          throw Exception('Inventory item not found');
        }

        final invData = invSnap.data() as Map<String, dynamic>;
        final currentStock = _asNum(invData['stockQty']).toInt();
        final currentQty = _asNum(orderData['qty']).toInt();
        final newQty = currentQty + delta;

        if (newQty <= 0) {
          throw Exception('Quantity cannot be zero or negative');
        }

        if (delta > 0 && currentStock < delta) {
          throw Exception('Not enough stock (available: $currentStock)');
        }

        final price = _asNum(orderData['price']);
        final newTotal = price * newQty;

        tx.update(orderRef, {
          'qty': newQty,
          'total': newTotal,
        });

        tx.update(invRef, {
          'stockQty': currentStock - delta,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final uid = FirebaseAuth.instance.currentUser?.uid;
        tx.set(invRef.collection('logs').doc(), {
          'type': delta > 0 ? 'usage' : 'return',
          'qty': delta > 0 ? -delta : delta.abs(),
          'at': FieldValue.serverTimestamp(),
          'note': 'Adjusted in session ${widget.sessionId}',
          if (uid != null) 'userId': uid,
        });
      });

      if (mounted) {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersStream = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId)
        .collection('orders')
        .snapshots();

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Session Orders',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'You can edit or remove orders before closing the bill.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: StreamBuilder<QuerySnapshot>(
                stream: ordersStream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  final orders = snap.data?.docs ?? [];

                  if (orders.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      child: const Text(
                        'No orders yet',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    );
                  }

                  num total = 0;
                  for (final doc in orders) {
                    final data = doc.data() as Map<String, dynamic>;
                    total += _asNum(data['total']);
                  }

                  return Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: orders.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                          itemBuilder: (_, i) {
                            final doc = orders[i];
                            final data = doc.data() as Map<String, dynamic>;
                            final itemName = data['itemName']?.toString() ?? 'Unknown';
                            final qty = _asNum(data['qty']).toInt();
                            final price = _asNum(data['price']);
                            final lineTotal = _asNum(data['total']);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          itemName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '₹${_fmt(price)} each',
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _updateQuantity(doc.id, data, -1),
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                                    iconSize: 20,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$qty',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _updateQuantity(doc.id, data, 1),
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
                                    iconSize: 20,
                                  ),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      '₹${_fmt(lineTotal)}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _removeOrder(doc.id, data),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    iconSize: 20,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(color: Colors.white24),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '₹${_fmt(total)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

num _asNum(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

String _fmt(num v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
