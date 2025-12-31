import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/branch_model.dart';
import 'add_edit_branch_screen.dart';
import '../seats/seats_screen.dart';

class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final branchesCol = FirebaseFirestore.instance.collection('branches');

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Branches',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textStrong,
                ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const AddEditBranchScreen(),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Branch'),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: branchesCol.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text('No branches yet.', style: TextStyle(color: AppTheme.textMute)));
                }

                final docs = snapshot.data!.docs;

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final d = docs[index];
                    final branch = BranchModel.fromMap(d.id, d.data() as Map<String, dynamic>);
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.bg2,
                        border: Border.all(color: AppTheme.outlineSoft),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.bg0,
                            child: Text(
                              branch.name.isNotEmpty ? branch.name[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppTheme.textStrong),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  branch.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: AppTheme.textStrong,
                                  ),
                                ),
                                if (branch.address != null && branch.address!.isNotEmpty)
                                  Text(
                                    branch.address!,
                                    style: const TextStyle(color: AppTheme.textMute),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: branch.active ? Colors.green.withOpacity(0.08) : Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              branch.active ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: branch.active ? Colors.green.shade300 : Colors.red.shade300,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Manage seats',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => SeatsScreen(
                                  branchId: branch.id,
                                  branchName: branch.name,
                                ),
                              );
                            },
                            icon: const Icon(Icons.chair_alt_outlined, color: AppTheme.textStrong),
                          ),
                          IconButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AddEditBranchScreen(existing: branch),
                              );
                            },
                            icon: const Icon(Icons.edit, color: AppTheme.textStrong),
                          ),
                          IconButton(
                            onPressed: () async {
                              await branchesCol.doc(branch.id).delete();
                            },
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
