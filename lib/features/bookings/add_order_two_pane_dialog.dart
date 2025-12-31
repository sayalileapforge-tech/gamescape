import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddOrderTwoPaneDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;
  final String? sessionLabel; // e.g. "Andheri • Seat 04 • Vishal"

  const AddOrderTwoPaneDialog({
    super.key,
    required this.branchId,
    required this.sessionId,
    this.sessionLabel,
  });

  @override
  State<AddOrderTwoPaneDialog> createState() => _AddOrderTwoPaneDialogState();
}

class _AddOrderTwoPaneDialogState extends State<AddOrderTwoPaneDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _committing = false;

  // cart: itemId -> { name, price, qty }
  final Map<String, _CartLine> _cart = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  num get _cartSubtotal {
    num t = 0;
    for (final e in _cart.values) {
      t += e.price * e.qty;
    }
    return t;
  }

  void _addToCart(String id, String name, num price, int stock) {
    setState(() {
      final existing = _cart[id];
      if (existing == null) {
        _cart[id] = _CartLine(id: id, name: name, price: price, qty: 1, stock: stock);
      } else {
        if (existing.qty < existing.stock) existing.qty += 1;
      }
    });
  }

  void _inc(String id) {
    setState(() {
      final e = _cart[id];
      if (e == null) return;
      if (e.qty < e.stock) e.qty += 1;
    });
  }

  void _dec(String id) {
    setState(() {
      final e = _cart[id];
      if (e == null) return;
      if (e.qty > 1) {
        e.qty -= 1;
      } else {
        _cart.remove(id);
      }
    });
  }

  void _remove(String id) {
    setState(() => _cart.remove(id));
  }

  Future<void> _commit({required bool closeAfter}) async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cart is empty')),
      );
      return;
    }
    setState(() => _committing = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final fs = FirebaseFirestore.instance;
    final sessionOrders = fs
        .collection('branches')
        .doc(widget.branchId)
        .collection('sessions')
        .doc(widget.sessionId)
        .collection('orders');

    try {
      // Check for existing orders BEFORE transaction
      final existingOrdersMap = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final line in _cart.values) {
        final existingOrderSnap = await sessionOrders
            .where('itemId', isEqualTo: line.id)
            .limit(1)
            .get();
        if (existingOrderSnap.docs.isNotEmpty) {
          existingOrdersMap[line.id] = existingOrderSnap.docs.first;
        }
      }

      await fs.runTransaction((tx) async {
        // 1) Read inventory docs & validate stock
        final invRefs = <String, DocumentReference<Map<String, dynamic>>>{};
        final invSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};

        for (final line in _cart.values) {
          final ref = fs
              .collection('branches')
              .doc(widget.branchId)
              .collection('inventory')
              .doc(line.id);
          invRefs[line.id] = ref;
          final snap = await tx.get(ref);
          invSnaps[line.id] = snap;
        }

        // 2) Validate stock
        for (final line in _cart.values) {
          final data = invSnaps[line.id]?.data() ?? {};
          final currentStock = _asNum(data['stockQty']).toInt();
          final existingQty = existingOrdersMap.containsKey(line.id) 
              ? _asNum(existingOrdersMap[line.id]!.data()?['qty']).toInt() 
              : 0;
          final stockNeeded = line.qty - existingQty;
          
          if (currentStock < stockNeeded) {
            throw Exception('Insufficient stock for "${line.name}" (have $currentStock, need $stockNeeded more)');
          }
        }

        // 3) Create/update order rows & adjust stock & write logs
        for (final line in _cart.values) {
          final total = (line.price * line.qty).toDouble();
          final existingOrder = existingOrdersMap[line.id];
          
          if (existingOrder != null) {
            // Update existing order
            tx.update(sessionOrders.doc(existingOrder.id), {
              'qty': line.qty,
              'price': line.price.toDouble(),
              'total': total,
            });
          } else {
            // Create new order
            final orderDoc = sessionOrders.doc();
            tx.set(orderDoc, {
              'itemId': line.id,
              'itemName': line.name,
              'qty': line.qty,
              'price': line.price.toDouble(),
              'total': total,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          final invRef = invRefs[line.id]!;
          final invData = invSnaps[line.id]!.data()!;
          final currentStock = _asNum(invData['stockQty']).toInt();
          final existingQty = existingOrder != null 
              ? _asNum(existingOrder.data()?['qty']).toInt() 
              : 0;
          final stockDelta = line.qty - existingQty;

          tx.update(invRef, {
            'stockQty': currentStock - stockDelta,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (stockDelta != 0) {
            final logRef = invRef.collection('logs').doc();
            tx.set(logRef, {
              'type': stockDelta > 0 ? 'usage' : 'return',
              'qty': stockDelta > 0 ? -stockDelta : stockDelta.abs(),
              'at': FieldValue.serverTimestamp(),
              'note': 'Used in session ${widget.sessionId}',
              if (uid != null) 'userId': uid,
            });
          }
        }
      });

      if (!mounted) return;

      if (closeAfter) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _cart.clear();
          _committing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Items added to session')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _committing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add items: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final invQuery = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory')
        .where('active', isEqualTo: true)
        .orderBy('name');

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 860,
        height: 540,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Add F&B to Session',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (widget.sessionLabel != null && widget.sessionLabel!.isNotEmpty)
                  Text(
                    'Adding to: ${widget.sessionLabel!}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Two panes
            Expanded(
              child: Row(
                children: [
                  // LEFT: Inventory list
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Search items',
                              hintStyle: TextStyle(color: Colors.white54),
                              prefixIcon: Icon(Icons.search, color: Colors.white60),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.white),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: invQuery.snapshots(),
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                final docs = snap.data?.docs ?? [];
                                final filtered = docs.where((d) {
                                  final name = (d.data()['name'] ?? '').toString().toLowerCase();
                                  final q = _searchCtrl.text.trim().toLowerCase();
                                  if (q.isEmpty) return true;
                                  return name.contains(q);
                                }).toList();

                                if (filtered.isEmpty) {
                                  return const Center(
                                    child: Text('No items found', style: TextStyle(color: Colors.white54)),
                                  );
                                }

                                return ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 8),
                                  itemBuilder: (_, i) {
                                    final d = filtered[i];
                                    final data = d.data();
                                    final name = (data['name'] ?? '').toString();
                                    final price = _asNum(data['price']);
                                    final stock = _asNum(data['stockQty']).toInt();
                                    final low = _asNum(data['reorderThreshold']).toInt();
                                    final isLow = stock <= low && low > 0;

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Text(name, style: const TextStyle(color: Colors.white)),
                                      subtitle: Text(
                                        '₹${_fmt(price)} • Stock: $stock${isLow ? '  (Low)' : ''}',
                                        style: TextStyle(
                                          color: isLow ? Colors.amberAccent : Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                      trailing: ElevatedButton.icon(
                                        onPressed: stock > 0 ? () => _addToCart(d.id, name, price, stock) : null,
                                        icon: const Icon(Icons.add, size: 16),
                                        label: const Text('Add'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: const Color(0xFF111827),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // RIGHT: Cart
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _cart.isEmpty
                                ? const Center(
                                    child: Text('No items yet. Add from the left list.',
                                        style: TextStyle(color: Colors.white54)),
                                  )
                                : ListView.separated(
                                    itemCount: _cart.values.length,
                                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 8),
                                    itemBuilder: (_, i) {
                                      final line = _cart.values.elementAt(i);
                                      final lineTotal = line.price * line.qty;
                                      final outOfStock = line.qty > line.stock;

                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(line.name, style: const TextStyle(color: Colors.white)),
                                                Text(
                                                  '₹${_fmt(line.price)} • Stock: ${line.stock}',
                                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                                ),
                                                if (outOfStock)
                                                  const Text(
                                                    'Quantity exceeds stock',
                                                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.remove, color: Colors.white70),
                                                onPressed: () => _dec(line.id),
                                              ),
                                              Text('${line.qty}', style: const TextStyle(color: Colors.white)),
                                              IconButton(
                                                icon: const Icon(Icons.add, color: Colors.white70),
                                                onPressed: () => _inc(line.id),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),
                                          Text('₹${_fmt(lineTotal)}',
                                              style: const TextStyle(color: Colors.white)),
                                          IconButton(
                                            tooltip: 'Remove',
                                            icon: const Icon(Icons.close, color: Colors.white54),
                                            onPressed: () => _remove(line.id),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                          ),
                          const Divider(color: Colors.white24),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Subtotal: ₹${_fmt(_cartSubtotal)}',
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                              ),
                              SizedBox(
                                height: 40,
                                child: OutlinedButton(
                                  onPressed: _committing ? null : () => _commit(closeAfter: false),
                                  child: _committing
                                      ? const SizedBox(
                                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('Add & keep open'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 40,
                                child: ElevatedButton(
                                  onPressed: _committing ? null : () => _commit(closeAfter: true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF111827),
                                    elevation: 0,
                                  ),
                                  child: _committing
                                      ? const SizedBox(
                                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('Add & close'),
                                ),
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
          ],
        ),
      ),
    );
  }
}

// ---- helpers ----
class _CartLine {
  final String id;
  final String name;
  final num price;
  int qty;
  final int stock;

  _CartLine({
    required this.id,
    required this.name,
    required this.price,
    required this.qty,
    required this.stock,
  });
}

num _asNum(dynamic v, {num fallback = 0}) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}

String _fmt(num v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
