import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../data/models/inventory_item_model.dart';

class AddEditInventoryItemDialog extends StatefulWidget {
  final String branchId;
  final InventoryItemModel? existing;
  const AddEditInventoryItemDialog({
    super.key,
    required this.branchId,
    this.existing,
  });

  @override
  State<AddEditInventoryItemDialog> createState() =>
      _AddEditInventoryItemDialogState();
}

class _AddEditInventoryItemDialogState
    extends State<AddEditInventoryItemDialog> {
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '0');
  final _stockCtrl = TextEditingController(text: '0');

  /// NEW: reorder / low-stock threshold
  final _reorderThresholdCtrl = TextEditingController(text: '0');

  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _skuCtrl.text = widget.existing!.sku ?? '';
      _priceCtrl.text = widget.existing!.price.toString();
      _stockCtrl.text = widget.existing!.stockQty.toString();
      _reorderThresholdCtrl.text =
          widget.existing!.reorderThreshold.toString();
      _active = widget.existing!.active;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _reorderThresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);

    final col = FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .collection('inventory');

    final price = num.tryParse(_priceCtrl.text.trim()) ?? 0;
    final stock = num.tryParse(_stockCtrl.text.trim()) ?? 0;
    final reorderThreshold =
        num.tryParse(_reorderThresholdCtrl.text.trim()) ?? 0;

    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (widget.existing == null) {
      // NEW ITEM
      final docRef = await col.add({
        'name': _nameCtrl.text.trim(),
        'sku': _skuCtrl.text.trim(),
        'price': price,
        'stockQty': stock,
        'reorderThreshold': reorderThreshold,
        'active': _active,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // write log
      await docRef.collection('logs').add({
        'type': 'add',
        'qty': stock,
        'at': FieldValue.serverTimestamp(),
        'note': 'Item created',
        if (uid != null) 'userId': uid,
      });
    } else {
      // UPDATE EXISTING
      final oldStock = widget.existing!.stockQty;
      final docRef = col.doc(widget.existing!.id);

      await docRef.update({
        'name': _nameCtrl.text.trim(),
        'sku': _skuCtrl.text.trim(),
        'price': price,
        'stockQty': stock,
        'reorderThreshold': reorderThreshold,
        'active': _active,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // write adjust log (only if stock changed)
      final stockDiff = stock - oldStock;
      await docRef.collection('logs').add({
        'type': 'adjust',
        'qty': stockDiff,
        'at': FieldValue.serverTimestamp(),
        'note': 'Item updated',
        'newStock': stock,
        if (uid != null) 'userId': uid,
      });
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? 'Add Inventory Item' : 'Edit Item',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Item name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _skuCtrl,
              decoration: const InputDecoration(
                labelText: 'SKU (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Price',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _stockCtrl,
              decoration: const InputDecoration(
                labelText: 'Stock quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),

            /// NEW FIELD: low-stock threshold
            TextField(
              controller: _reorderThresholdCtrl,
              decoration: const InputDecoration(
                labelText: 'Low stock threshold (reorder level)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),

            const SizedBox(height: 10),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Active'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
