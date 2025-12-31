import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/inventory_item_model.dart';
import 'add_edit_inventory_item.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String? _selectedBranchId;
  String? _selectedBranchName;

  @override
  Widget build(BuildContext context) {
    final branchesCol = FirebaseFirestore.instance.collection('branches');
    final user = FirebaseAuth.instance.currentUser;

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: user != null
                      ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots()
                      : null,
                  builder: (context, userSnap) {
                    final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                    final role = (userData['role'] ?? 'staff').toString();
                    final List<dynamic> branchIdsDyn = (userData['branchIds'] as List<dynamic>?) ?? [];
                    final allowedBranchIds = branchIdsDyn.map((e) => e.toString()).toList();

                    return StreamBuilder<QuerySnapshot>(
                      stream: branchesCol.snapshots(),
                      builder: (context, snapshot) {
                        final allDocs = snapshot.hasData
                            ? snapshot.data!.docs
                            : <QueryDocumentSnapshot>[];
                        // Filter branches: ONLY superadmin sees all, everyone else filtered by branchIds
                        final docs = (role == 'superadmin')
                            ? allDocs
                            : allDocs.where((b) => allowedBranchIds.contains(b.id)).toList();
                    return DropdownButtonFormField<String>(
                      value: _selectedBranchId,
                      dropdownColor: const Color(0xFF111827),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Select branch',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white38),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                      ),
                      items: docs.map((d) {
                        return DropdownMenuItem(
                          value: d.id,
                          child: Text(d['name'] ?? 'Branch'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedBranchId = v;
                          final doc = docs.firstWhere((e) => e.id == v);
                          _selectedBranchName = doc['name'] ?? '';
                        });
                      },
                    );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _selectedBranchId == null
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (_) => AddEditInventoryItemDialog(
                            branchId: _selectedBranchId!,
                          ),
                        );
                      },
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _selectedBranchId == null
                ? const Center(
                    child: Text('Select a branch to view inventory',
                        style: TextStyle(color: Colors.white70)))
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('branches')
                        .doc(_selectedBranchId)
                        .collection('inventory')
                        .orderBy('name')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData ||
                          snapshot.data!.docs.isEmpty) {
                        return const Center(
                            child: Text('No items yet.',
                                style: TextStyle(color: Colors.white70)));
                      }

                      final docs = snapshot.data!.docs;
                      final items = docs
                          .map((d) => InventoryItemModel.fromMap(
                              d.id, d.data() as Map<String, dynamic>))
                          .toList();

                      final lowStock =
                          items.where((e) => e.stockQty <= 2).toList();

                      return Column(
                        children: [
                          if (lowStock.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB91C1C).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Low stock alerts',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: lowStock.map((i) {
                                      return Chip(
                                        label: Text(
                                          '${i.name} (${i.stockQty})',
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                        backgroundColor: Colors.red
                                            .withOpacity(0.25),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2937),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                  dataTextStyle:
                                      const TextStyle(color: Colors.white),
                                  columns: const [
                                    DataColumn(label: Text('Name')),
                                    DataColumn(label: Text('Price')),
                                    DataColumn(label: Text('Stock')),
                                    DataColumn(label: Text('SKU')),
                                    DataColumn(label: Text('Status')),
                                    DataColumn(label: Text('Actions')),
                                  ],
                                  rows: items.map((item) {
                                    return DataRow(cells: [
                                      DataCell(Text(item.name)),
                                      DataCell(Text('₹${item.price}')),
                                      DataCell(Text(item.stockQty.toString())),
                                      DataCell(Text(item.sku ?? '-')),
                                      DataCell(Text(
                                        item.active ? 'Active' : 'Inactive',
                                        style: TextStyle(
                                          color: item.active
                                              ? Colors.greenAccent
                                              : Colors.redAccent,
                                        ),
                                      )),
                                      DataCell(
                                        Row(
                                          children: [
                                            IconButton(
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (_) =>
                                                      AddEditInventoryItemDialog(
                                                    branchId:
                                                        _selectedBranchId!,
                                                    existing: item,
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.edit,
                                                  color: Colors.white),
                                            ),
                                            IconButton(
                                              onPressed: () async {
                                                final uid =
                                                    FirebaseAuth.instance
                                                        .currentUser?.uid;
                                                final invDoc =
                                                    FirebaseFirestore.instance
                                                        .collection('branches')
                                                        .doc(_selectedBranchId)
                                                        .collection('inventory')
                                                        .doc(item.id);

                                                await invDoc
                                                    .collection('logs')
                                                    .add({
                                                  'type': 'delete',
                                                  'qty': item.stockQty,
                                                  'at': FieldValue
                                                      .serverTimestamp(),
                                                  'note':
                                                      'Item deleted from inventory screen',
                                                  if (uid != null)
                                                    'userId': uid,
                                                });

                                                await invDoc.delete();
                                              },
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Colors.redAccent),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
