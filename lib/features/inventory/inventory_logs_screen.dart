import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/app_shell.dart';

class InventoryLogsScreen extends StatefulWidget {
  const InventoryLogsScreen({super.key});

  @override
  State<InventoryLogsScreen> createState() => _InventoryLogsScreenState();
}

class _InventoryLogsScreenState extends State<InventoryLogsScreen> {
  String? _selectedBranchId;
  String? _selectedItemId;

  @override
  Widget build(BuildContext context) {
    final branchesCol = FirebaseFirestore.instance.collection('branches');
    final user = FirebaseAuth.instance.currentUser;

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory Logs',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 16),
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
                        final allBranches = snapshot.data?.docs ?? [];
                        // Filter branches: ONLY superadmin sees all, everyone else filtered by branchIds
                        final branches = (role == 'superadmin')
                            ? allBranches
                            : allBranches.where((b) => allowedBranchIds.contains(b.id)).toList();
                        return DropdownButtonFormField<String>(
                          value: _selectedBranchId,
                          decoration: const InputDecoration(
                            labelText: 'Select branch',
                            labelStyle: TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white),
                            ),
                          ),
                          dropdownColor: const Color(0xFF111827),
                          style: const TextStyle(color: Colors.white),
                          items: branches
                              .map((b) => DropdownMenuItem(
                                    value: b.id,
                                    child: Text(b['name'] ?? 'Branch'),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedBranchId = v;
                              _selectedItemId = null;
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              if (_selectedBranchId != null)
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: branchesCol.doc(_selectedBranchId).collection('inventory').snapshots(),
                    builder: (context, snapshot) {
                      final items = snapshot.data?.docs ?? [];
                      return DropdownButtonFormField<String>(
                        value: _selectedItemId,
                        decoration: const InputDecoration(
                          labelText: 'Select item',
                          labelStyle: TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white),
                          ),
                        ),
                        dropdownColor: const Color(0xFF111827),
                        style: const TextStyle(color: Colors.white),
                        items: items
                            .map((i) => DropdownMenuItem(
                                  value: i.id,
                                  child: Text(i['name'] ?? 'Item'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedItemId = v;
                          });
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _selectedBranchId == null || _selectedItemId == null
                ? const Center(
                    child: Text('Select a branch and item to view logs', style: TextStyle(color: Colors.white54)),
                  )
                : _InventoryLogsList(branchId: _selectedBranchId!, itemId: _selectedItemId!),
          ),
        ],
      ),
    );
  }
}

class _InventoryLogsList extends StatelessWidget {
  final String branchId;
  final String itemId;
  const _InventoryLogsList({required this.branchId, required this.itemId});

  Color _typeColor(String t) {
    switch (t) {
      case 'usage':
        return Colors.orangeAccent; // consumption
      case 'adjustment':
        return Colors.cyanAccent; // manual +/- or import delta
      case 'add':
        return Colors.greenAccent; // legacy/add
      default:
        return Colors.white;
    }
  }

  String _signed(num qty) => (qty >= 0 ? '+$qty' : '$qty');

  @override
  Widget build(BuildContext context) {
    final logsRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('inventory')
        .doc(itemId)
        .collection('logs')
        .orderBy('at', descending: true);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: logsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final logs = snapshot.data?.docs ?? [];
          if (logs.isEmpty) {
            return const Center(
              child: Text('No logs found for this item.', style: TextStyle(color: Colors.white54)),
            );
          }
          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final d = logs[index].data() as Map<String, dynamic>? ?? {};
              final type = d['type']?.toString() ?? 'log'; // usage | adjustment | add
              final qty = d['qty'] is num ? d['qty'] as num : num.tryParse('${d['qty']}') ?? 0;
              final at = (d['at'] as Timestamp?)?.toDate();
              final note = d['note']?.toString() ?? '';
              final userId = d['userId']?.toString() ?? '';

              return ListTile(
                dense: true,
                title: Text(
                  '${type.toUpperCase()} • ${_signed(qty)}',
                  style: TextStyle(color: _typeColor(type), fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${at ?? ''}${note.isNotEmpty ? ' • $note' : ''}${userId.isNotEmpty ? ' • by $userId' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
