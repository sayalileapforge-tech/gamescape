import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AddOrderDialog extends StatefulWidget {
  final String branchId;
  final String sessionId;

  const AddOrderDialog({
    super.key,
    required this.branchId,
    required this.sessionId,
  });

  @override
  State<AddOrderDialog> createState() => _AddOrderDialogState();
}

class _AddOrderDialogState extends State<AddOrderDialog> {
  final TextEditingController _searchCtrl = TextEditingController();

  /// cart[itemId] = _CartLine(...)
  final Map<String, _CartLine> _cart = {};
  bool _saving = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  num get _cartSubtotal {
    num sum = 0;
    for (final line in _cart.values) {
      sum += (line.price * line.qty);
    }
    return sum;
  }

  void _addOne(_InventoryItem it) {
    final existing = _cart[it.id];
    if (existing == null) {
      if (it.stock <= 0) return;
      setState(() {
        _cart[it.id] = _CartLine(
          itemId: it.id,
          name: it.name,
          price: it.price,
          qty: 1,
          stockLeft: it.stock,
        );
      });
    } else {
      if (existing.qty >= existing.stockLeft) return;
      setState(() {
        existing.qty += 1;
      });
    }
  }

  void _decOne(String itemId) {
    final line = _cart[itemId];
    if (line == null) return;
    setState(() {
      if (line.qty <= 1) {
        _cart.remove(itemId);
      } else {
        line.qty -= 1;
      }
    });
  }

  void _incOne(String itemId) {
    final line = _cart[itemId];
    if (line == null) return;
    if (line.qty >= line.stockLeft) return;
    setState(() {
      line.qty += 1;
    });
  }

  Future<void> _saveAndClose() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one item')),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final fs = FirebaseFirestore.instance;
      final sessionOrders = fs
          .collection('branches')
          .doc(widget.branchId)
          .collection('sessions')
          .doc(widget.sessionId)
          .collection('orders');

      final now = FieldValue.serverTimestamp();
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Each cart line in its own transaction so stock & line stay consistent
      for (final line in _cart.values) {
        // Check for existing order BEFORE transaction
        final existingOrderSnap = await sessionOrders
            .where('itemId', isEqualTo: line.itemId)
            .limit(1)
            .get();
        final existingOrder = existingOrderSnap.docs.isNotEmpty ? existingOrderSnap.docs.first : null;

        final invDoc = fs
            .collection('branches')
            .doc(widget.branchId)
            .collection('inventory')
            .doc(line.itemId);

        await fs.runTransaction((tx) async {
          final invSnap = await tx.get(invDoc);
          final inv = (invSnap.data() ?? {}) as Map<String, dynamic>;
          final currentStock = _num(inv['stockQty']).toInt();
          final priceNow = _num(inv['price']).toDouble();

          final want = line.qty;
          final int stockNeeded;
          final int existingQty;

          if (existingOrder != null) {
            // Update existing order
            existingQty = _num(existingOrder.data()['qty']).toInt();
            stockNeeded = want - existingQty;
          } else {
            // New order
            existingQty = 0;
            stockNeeded = want;
          }

          if (currentStock < stockNeeded) {
            throw Exception('${line.name} only $currentStock left (need $stockNeeded more)');
          }

          final total = priceNow * want;

          if (existingOrder != null) {
            // Update existing order
            tx.update(sessionOrders.doc(existingOrder.id), {
              'qty': want,
              'price': priceNow,
              'total': total,
            });
          } else {
            // Create new order
            final lineRef = sessionOrders.doc();
            tx.set(lineRef, {
              'itemId': line.itemId,
              'itemName': line.name,
              'qty': want,
              'price': priceNow,
              'total': total,
              'createdAt': now,
            });
          }

          // Adjust stock by the difference
          tx.update(invDoc, {
            'stockQty': currentStock - stockNeeded,
            'updatedAt': now,
          });

          // Log the stock change
          if (stockNeeded != 0) {
            tx.set(invDoc.collection('logs').doc(), {
              'type': stockNeeded > 0 ? 'usage' : 'return',
              'qty': stockNeeded > 0 ? -stockNeeded : stockNeeded.abs(),
              'at': now,
              'note': 'Used in session ${widget.sessionId}',
              if (uid != null) 'userId': uid,
            });
          }
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsQuery = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory')
        .where('active', isEqualTo: true);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: const Color(0xFF0F172A),
      child: SizedBox(
        width: 900,
        height: 560,
        child: Row(
          children: [
            // LEFT: Inventory + search
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Order',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, color: Colors.white70),
                        hintText: 'Search items',
                        hintStyle: TextStyle(color: Colors.white54),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: itemsQuery.snapshots(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snap.data?.docs ?? [];
                          final all = docs.map((d) {
                            final m = (d.data() as Map<String, dynamic>? ?? {});
                            return _InventoryItem(
                              id: d.id,
                              name: (m['name'] ?? '').toString(),
                              price: _num(m['price']),
                              stock: _num(m['stockQty']).toInt(),
                            );
                          }).toList();

                          final query = _searchCtrl.text.trim().toLowerCase();
                          final filtered = query.isEmpty
                              ? all
                              : all.where((e) => e.name.toLowerCase().contains(query)).toList();

                          if (filtered.isEmpty) {
                            return const Center(
                              child: Text('No items', style: TextStyle(color: Colors.white54)),
                            );
                          }

                          return GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisExtent: 110,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final it = filtered[i];
                              final out = it.stock <= 0;
                              return InkWell(
                                onTap: out ? null : () => _addOne(it),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: out ? Colors.white10 : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12, width: 1),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        it.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                      ),
                                      const Spacer(),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('₹${_fmt(it.price)}', style: const TextStyle(color: Colors.white70)),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(999),
                                              color: Colors.white12,
                                            ),
                                            child: Text(
                                              out ? 'Out' : 'Stock: ${it.stock}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
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

            const SizedBox(width: 16),

            // RIGHT: Cart
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Items added',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _cart.isEmpty
                          ? const Center(child: Text('No items yet', style: TextStyle(color: Colors.white54)))
                          : ListView.separated(
                              itemCount: _cart.length,
                              separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                              itemBuilder: (_, idx) {
                                final line = _cart.values.elementAt(idx);
                                final total = line.price * line.qty;
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(line.name,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text('₹${_fmt(line.price)} each',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _decOne(line.itemId),
                                      icon: const Icon(Icons.remove, color: Colors.white70),
                                    ),
                                    Text('${line.qty}', style: const TextStyle(color: Colors.white)),
                                    IconButton(
                                      onPressed: () => _incOne(line.itemId),
                                      icon: const Icon(Icons.add, color: Colors.white70),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '₹${_fmt(total)}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal', style: TextStyle(color: Colors.white70)),
                        Text(
                          '₹${_fmt(_cartSubtotal)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ✅ Only ONE CTA now
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveAndClose,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Add & close'),
                      ),
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
}

// ===== Helpers =====

class _InventoryItem {
  final String id;
  final String name;
  final num price;
  final int stock;

  _InventoryItem({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
  });
}

class _CartLine {
  final String itemId;
  final String name;
  final num price;
  int qty;
  final int stockLeft;

  _CartLine({
    required this.itemId,
    required this.name,
    required this.price,
    required this.qty,
    required this.stockLeft,
  });
}

num _num(dynamic v, {num fallback = 0}) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? fallback;
  return fallback;
}

String _fmt(num v) => v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
