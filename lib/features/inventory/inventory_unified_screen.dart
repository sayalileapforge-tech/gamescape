// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/models/inventory_item_model.dart';
import 'add_edit_inventory_item.dart';

class InventoryUnifiedScreen extends StatefulWidget {
  const InventoryUnifiedScreen({super.key});

  @override
  State<InventoryUnifiedScreen> createState() => _InventoryUnifiedScreenState();
}

class _InventoryUnifiedScreenState extends State<InventoryUnifiedScreen> {
  String? _branchId;
  String? _selectedItemId;

  // search (debounced)
  String _searchRaw = '';
  String _search = '';
  Timer? _debounce;

  // filters
  bool _lowOnly = false;
  final _snackedLow = <String>{};

  // pagination
  static const int _limit = 100;
  int _page = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _setSearch(String v) {
    _debounce?.cancel();
    _searchRaw = v;
    _debounce = Timer(const Duration(milliseconds: 280), () {
      setState(() => _search = _searchRaw.trim().toLowerCase());
    });
  }

  void _resetPaging() => setState(() => _page = 1);
  void _loadMore() => setState(() => _page += 1);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory (Unified)',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _BranchDropdown(
                value: _branchId,
                onChanged: (id) {
                  setState(() {
                    _branchId = id;
                    _selectedItemId = null;
                  });
                  _resetPaging();
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search item…',
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.search, color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: _setSearch,
                ),
              ),
              const SizedBox(width: 10),
              _FilterChip(
                label: 'Low stock',
                selected: _lowOnly,
                onTap: () {
                  setState(() => _lowOnly = !_lowOnly);
                  _resetPaging();
                },
              ),
              const SizedBox(width: 10),
              // NEW: Create Item button
              ElevatedButton.icon(
                onPressed: (_branchId == null)
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (_) => AddEditInventoryItemDialog(
                            branchId: _branchId!,
                            existing: null,
                          ),
                        );
                      },
                icon: const Icon(Icons.add),
                label: const Text('Create Item'),
              ),
              const SizedBox(width: 10),
              // IMPORT CSV
              ElevatedButton.icon(
                onPressed: (_branchId == null) ? null : () => _importCsvForBranch(_branchId!),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Import CSV'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _downloadTemplateCsv,
                child: const Text('Download template'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _branchId == null
                ? const _CenteredNote('Select a branch to view inventory.')
                : Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _InventoryListPane(
                          key: ValueKey('inv-left-$_branchId-$_page-$_lowOnly-$_search'),
                          branchId: _branchId!,
                          search: _search,
                          lowOnly: _lowOnly,
                          page: _page,
                          limit: _limit,
                          selectedItemId: _selectedItemId,
                          onPick: (id) => setState(() => _selectedItemId = id),
                          onLow: (id, name) {
                            // toast only once per session
                            if (_snackedLow.add(id)) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text('Low stock: $name'),
                                  ),
                                );
                              });
                            }
                          },
                          onLoadMore: _loadMore,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 7,
                        child: _selectedItemId == null
                            ? const _CenteredNote('Select an item to view details & logs.')
                            : _ItemDetailWithLogs(
                                branchId: _branchId!,
                                itemId: _selectedItemId!,
                                onOpenEdit: (doc) {
                                  final data = (doc.data() as Map<String, dynamic>? ?? {});
                                  final model = InventoryItemModel.fromMap(doc.id, data);
                                  showDialog(
                                    context: context,
                                    builder: (_) => AddEditInventoryItemDialog(
                                      branchId: _branchId!,
                                      existing: model,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ----- CSV helpers -----

  void _downloadTemplateCsv() {
    const csv = 'name,price,stockQty,reorderThreshold,sku,active\n'
        'Pepsi 500ml,40,24,6,PEP500,true\n'
        'Fries,120,10,3,FRIES120,true\n';
    final bytes = html.Blob([csv], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(bytes);
    final a = html.AnchorElement(href: url)
      ..download = 'inventory_template.csv'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _importCsvForBranch(String branchId) async {
    final input = html.FileUploadInputElement()..accept = '.csv';
    input.click();

    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;

    final file = input.files!.first;
    final reader = html.FileReader();
    reader.readAsText(file);
    await reader.onLoad.first;

    final content = reader.result?.toString() ?? '';
    if (content.trim().isEmpty) return;

    final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;

    // parse header
    final header = _splitCsvLine(lines.first);
    final nameIdx = header.indexOf('name');
    final priceIdx = header.indexOf('price');
    final stockIdx = header.indexOf('stockQty');
    final threshIdx = header.indexOf('reorderThreshold');
    final skuIdx = header.indexOf('sku');
    final activeIdx = header.indexOf('active');

    if (nameIdx < 0) {
      _toast('CSV missing "name" column');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final invCol = FirebaseFirestore.instance.collection('branches').doc(branchId).collection('inventory');

    int imported = 0, updated = 0;

    // process rows
    for (var i = 1; i < lines.length; i++) {
      final row = _splitCsvLine(lines[i]);
      if (row.every((c) => c.trim().isEmpty)) continue;

      String name = _getOrNull(row, nameIdx)?.trim() ?? '';
      num price = _parseNum(_getOrNull(row, priceIdx));
      int stockQty = _parseInt(_getOrNull(row, stockIdx));
      int reorderThreshold = _parseInt(_getOrNull(row, threshIdx));
      String? sku = _getOrNull(row, skuIdx)?.trim();
      bool active = _parseBool(_getOrNull(row, activeIdx), defaultValue: true);

      if (name.isEmpty) continue;

      // find existing by SKU (if present), else by exact name
      QueryDocumentSnapshot? existing;
      if (sku != null && sku.isNotEmpty) {
        final q = await invCol.where('sku', isEqualTo: sku).limit(1).get();
        if (q.docs.isNotEmpty) existing = q.docs.first;
      }
      if (existing == null) {
        final q = await invCol.where('name', isEqualTo: name).limit(1).get();
        if (q.docs.isNotEmpty) existing = q.docs.first;
      }

      if (existing == null) {
        // create new item
        final docRef = await invCol.add({
          'name': name,
          'price': (price is double) ? price : (price.toDouble()),
          'stockQty': stockQty,
          'reorderThreshold': reorderThreshold,
          'sku': sku,
          'active': active,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // initial stock log (adjustment = +stockQty)
        if (stockQty != 0) {
          await docRef.collection('logs').add({
            'type': 'adjustment',
            'qty': stockQty,
            'note': 'Bulk import',
            'at': FieldValue.serverTimestamp(),
            'userId': user?.uid ?? 'system',
          });
        }
        imported++;
      } else {
        // update existing; compute delta for log if stock changes
        final data = existing.data() as Map<String, dynamic>? ?? {};
        final currentStock = (data['stockQty'] is num) ? (data['stockQty'] as num).toInt() : 0;
        final delta = stockQty - currentStock;

        await invCol.doc(existing.id).update({
          'name': name,
          'price': (price is double) ? price : (price.toDouble()),
          'stockQty': stockQty,
          'reorderThreshold': reorderThreshold,
          'sku': sku,
          'active': active,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (delta != 0) {
          await invCol.doc(existing.id).collection('logs').add({
            'type': 'adjustment',
            'qty': delta,
            'note': 'Bulk import',
            'at': FieldValue.serverTimestamp(),
            'userId': user?.uid ?? 'system',
          });
        }
        updated++;
      }
    }

    _toast('Import complete: $imported added, $updated updated.');
  }

  List<String> _splitCsvLine(String line) {
    // simple CSV splitter with quotes
    final out = <String>[];
    final buf = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out.map((s) => s.replaceAll('""', '"')).toList();
  }

  String? _getOrNull(List<String> row, int index) {
    if (index < 0 || index >= row.length) return null;
    return row[index];
  }

  num _parseNum(String? s) {
    if (s == null) return 0;
    final t = s.trim();
    if (t.isEmpty) return 0;
    return num.tryParse(t) ?? 0;
  }

  int _parseInt(String? s) => _parseNum(s).toInt();

  bool _parseBool(String? s, {bool defaultValue = true}) {
    if (s == null) return defaultValue;
    final t = s.trim().toLowerCase();
    if (t == 'true' || t == '1' || t == 'yes') return true;
    if (t == 'false' || t == '0' || t == 'no') return false;
    return defaultValue;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}

// ---------- Left pane with pagination ----------
class _InventoryListPane extends StatelessWidget {
  final String branchId;
  final String search;
  final bool lowOnly;
  final String? selectedItemId;
  final int page;
  final int limit;
  final void Function(String) onPick;
  final void Function(String, String) onLow;
  final VoidCallback onLoadMore;

  const _InventoryListPane({
    super.key,
    required this.branchId,
    required this.search,
    required this.lowOnly,
    required this.selectedItemId,
    required this.page,
    required this.limit,
    required this.onPick,
    required this.onLow,
    required this.onLoadMore,
  });

  num _n(Map<String, dynamic> m, String key, {num fallback = 0}) {
    final v = m[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? fallback;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('inventory')
        .orderBy('name')
        .limit(limit * page); // incremental paging while staying live

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final docs = snap.data?.docs ?? [];

          final filtered = docs.where((d) {
            final m = (d.data() as Map<String, dynamic>? ?? {});
            final name = (m['name'] ?? '').toString().toLowerCase();
            final sku = (m['sku'] ?? '').toString().toLowerCase();
            if (search.isNotEmpty && !(name.contains(search) || sku.contains(search))) {
              return false;
            }
            if (lowOnly) {
              final stock = _n(m, 'stockQty');
              final thresh = _n(m, 'reorderThreshold');
              if (!(stock <= thresh)) return false;
            }
            return true;
          }).toList();

          if (filtered.isEmpty) {
            return const _CenteredNote('No items.');
          }

          return Column(
            children: [
              Expanded(
                child: ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final id = d.id;
                    final m = (d.data() as Map<String, dynamic>? ?? {});
                    final name = (m['name'] ?? '').toString();
                    final stock = _n(m, 'stockQty');
                    final thresh = _n(m, 'reorderThreshold');
                    final low = stock <= thresh;
                    final selected = selectedItemId == id;

                    if (low) onLow(id, name);

                    return InkWell(
                      onTap: () => onPick(id),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFF0F172A) : const Color(0xFF111827),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: selected ? Colors.white24 : Colors.white12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text('Stock: $stock', style: const TextStyle(color: Colors.white70)),
                            const SizedBox(width: 8),
                            if (low)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.15),
                                  border: Border.all(color: Colors.redAccent),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text('Low', style: TextStyle(color: Colors.redAccent)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Load more when we've exactly filled the current page size
              if (docs.length >= limit * page)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more, color: Colors.white),
                    label: const Text('Load more', style: TextStyle(color: Colors.white)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------- Right pane ----------
class _ItemDetailWithLogs extends StatelessWidget {
  final String branchId;
  final String itemId;
  final void Function(DocumentSnapshot doc) onOpenEdit;

  const _ItemDetailWithLogs({
    required this.branchId,
    required this.itemId,
    required this.onOpenEdit,
  });

  num _n(Map<String, dynamic> m, String key, {num fallback = 0}) {
    final v = m[key];
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? fallback;
    return fallback;
  }

  Color _typeColor(String t) {
    switch (t) {
      case 'usage':
        return Colors.orangeAccent;
      case 'adjustment':
        return Colors.cyanAccent;
      default:
        return Colors.white;
    }
  }

  String _signed(num qty) => (qty >= 0 ? '+$qty' : '$qty');

  @override
  Widget build(BuildContext context) {
    final itemRef = FirebaseFirestore.instance
        .collection('branches')
        .doc(branchId)
        .collection('inventory')
        .doc(itemId);

    return StreamBuilder<DocumentSnapshot>(
      stream: itemRef.snapshots(),
      builder: (context, itemSnap) {
        if (!itemSnap.hasData) {
          return const _CenteredNote('Loading item…');
        }
        final item = itemSnap.data!;
        final data = item.data() as Map<String, dynamic>? ?? {};
        final name = (data['name'] ?? '').toString();
        final stock = _n(data, 'stockQty');
        final price = _n(data, 'price');
        final thresh = _n(data, 'reorderThreshold');
        final low = stock <= thresh;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const SizedBox(width: 8),
                            if (low)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.15),
                                  border: Border.all(color: Colors.redAccent),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text('Low stock', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'In stock: $stock • Price: ₹$price • Reorder at: $thresh',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pillBtn(
                        icon: Icons.fastfood_outlined,
                        label: 'Add Usage',
                        onTap: () => _showUsageDialog(context, itemRef, name),
                      ),
                      _pillBtn(
                        icon: Icons.add_box_outlined,
                        label: 'Adjust Stock',
                        onTap: () => _showAdjustDialog(context, itemRef, name),
                      ),
                      _pillBtn(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onTap: () => onOpenEdit(item),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(12),
                child: StreamBuilder<QuerySnapshot>(
                  stream: itemRef.collection('logs').orderBy('at', descending: true).snapshots(),
                  builder: (context, logSnap) {
                    if (logSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.white));
                    }
                    final rows = logSnap.data?.docs ?? [];
                    if (rows.isEmpty) {
                      return const _CenteredNote('No logs for this item.');
                    }

                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
                      itemBuilder: (context, i) {
                        final r = rows[i].data() as Map<String, dynamic>? ?? {};
                        final type = (r['type'] ?? '').toString(); // usage | adjustment
                        final qty = r['qty'] is num ? r['qty'] as num : num.tryParse('${r['qty']}') ?? 0;
                        final at = (r['at'] as Timestamp?)?.toDate();
                        final note = (r['note'] ?? '').toString();
                        final user = (r['userId'] ?? '').toString();

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${type.toUpperCase()}  •  ${_signed(qty)}',
                            style: TextStyle(color: _typeColor(type), fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${at ?? ''}  •  ${note.isNotEmpty ? note : '-'}  •  ${user.isNotEmpty ? user : '-'}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // dialogs + stock change logic
  Future<void> _showUsageDialog(BuildContext context, DocumentReference itemRef, String name) async {
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'Order usage');
    await showDialog(
      context: context,
      builder: (_) => _QtyDialog(
        title: 'Add Usage – $name',
        okLabel: 'Save',
        qtyHint: 'Qty to deduct (e.g. 1)',
        qtyController: qtyCtrl,
        noteController: noteCtrl,
        onSubmit: () async {
          final n = int.tryParse(qtyCtrl.text.trim()) ?? 0;
          if (n <= 0) return;
          await _changeStockWithLog(
            itemRef: itemRef,
            delta: -n, // always negative for usage
            type: 'usage',
            note: noteCtrl.text.trim(),
          );
        },
      ),
    );
  }

  Future<void> _showAdjustDialog(BuildContext context, DocumentReference itemRef, String name) async {
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'Manual adjustment');
    await showDialog(
      context: context,
      builder: (_) => _QtyDialog(
        title: 'Adjust Stock – $name',
        okLabel: 'Apply',
        qtyHint: '± Qty (e.g. 5 or -3)',
        qtyController: qtyCtrl,
        noteController: noteCtrl,
        onSubmit: () async {
          final n = int.tryParse(qtyCtrl.text.trim()) ?? 0;
          if (n == 0) return;
          await _changeStockWithLog(
            itemRef: itemRef,
            delta: n, // can be + or -
            type: 'adjustment',
            note: noteCtrl.text.trim(),
          );
        },
      ),
    );
  }

  Future<void> _changeStockWithLog({
    required DocumentReference itemRef,
    required int delta,
    required String type, // usage|adjustment
    required String note,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final logsRef = itemRef.collection('logs').doc();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(itemRef);
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final current = (data['stockQty'] is num) ? (data['stockQty'] as num).toInt() : 0;
      final updated = (current + delta);
      final safeUpdated = updated < 0 ? 0 : updated;

      tx.update(itemRef, {
        'stockQty': safeUpdated,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(logsRef, {
        'type': type,
        'qty': delta,
        'note': note,
        'at': FieldValue.serverTimestamp(),
        'userId': user?.uid ?? 'system',
      });
    });
  }
}

// ---- small helpers
class _BranchDropdown extends StatelessWidget {
  final String? value;
  final void Function(String?) onChanged;
  const _BranchDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: user != null
          ? FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots()
          : null,
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final role = (userData['role'] ?? 'staff').toString();
        final List<dynamic> branchIdsDyn = (userData['branchIds'] as List<dynamic>?) ?? [];
        final allowedBranchIds = branchIdsDyn.map((e) => e.toString()).toList();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('branches').orderBy('name').snapshots(),
          builder: (context, snap) {
            final allItems = snap.data?.docs ?? [];
            // Filter branches: ONLY superadmin sees all, everyone else filtered by branchIds
            final items = (role == 'superadmin')
                ? allItems
                : allItems.where((b) => allowedBranchIds.contains(b.id)).toList();
            final current = (value != null && items.any((d) => d.id == value)) ? value : (items.isNotEmpty ? items.first.id : null);

            if (value == null && current != null) {
              Future.microtask(() => onChanged(current));
            }

            return SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                value: current,
                dropdownColor: const Color(0xFF111827),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Select branch',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
                items: items
                    .map((b) {
                      final data = (b.data() as Map<String, dynamic>? ?? {});
                      final label = (data['name'] ?? b.id).toString();
                      return DropdownMenuItem(value: b.id, child: Text(label));
                    })
                    .toList(),
                onChanged: onChanged,
              ),
            );
          },
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontSize: 12)),
      ),
    );
  }
}

class _QtyDialog extends StatelessWidget {
  final String title;
  final String okLabel;
  final String qtyHint;
  final TextEditingController qtyController;
  final TextEditingController noteController;
  final Future<void> Function() onSubmit;

  const _QtyDialog({
    required this.title,
    required this.okLabel,
    required this.qtyHint,
    required this.qtyController,
    required this.noteController,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: qtyController,
              decoration: InputDecoration(
                labelText: qtyHint,
                labelStyle: const TextStyle(color: Colors.white70),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await onSubmit();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(okLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredNote extends StatelessWidget {
  final String text;
  const _CenteredNote(this.text);
  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, style: const TextStyle(color: Colors.white54)));
  }
}

Widget _pillBtn({required IconData icon, required String label, required VoidCallback onTap}) {
  return ElevatedButton.icon(
    onPressed: onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}
