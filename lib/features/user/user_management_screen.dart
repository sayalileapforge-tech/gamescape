import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/app_shell.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return AppShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'User Management',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          const _RoleHelpNote(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final result = await showDialog<_CreateUserResult>(
                  context: context,
                  builder: (_) => const _CreateUserDialog(),
                );

                if (result != null && context.mounted) {
                  // Verify userId is present
                  if (result.userId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User created but ID missing. Please refresh.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  // Step 2: Show permissions dialog
                  final permissionsSaved = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _PermissionsDialog(
                      userId: result.userId,
                      userRole: result.role,
                    ),
                  );

                  if (permissionsSaved == true && context.mounted) {
                    // Step 3: Show temp password if present
                    if (result.tempPassword != null &&
                        result.tempPassword!.isNotEmpty) {
                      await showDialog<void>(
                        context: context,
                        builder: (_) => _TempPasswordDialog(
                          email: result.email,
                          password: result.tempPassword!,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User created successfully')),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text(
                'Create User',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final d = docs[index];
                    final data = d.data() as Map<String, dynamic>? ?? {};
                    final name = data['name']?.toString() ?? 'User';
                    final email = data['email']?.toString() ?? '';
                    final role = data['role']?.toString() ?? 'staff';
                    final branches =
                        (data['branchIds'] as List?)?.cast<String>() ?? [];

                    String branchLabel = '';
                    if (branches.isNotEmpty) {
                      branchLabel = (role == 'staff')
                          ? 'Branch: ${branches.length}'
                          : 'Branches: ${branches.length}';
                    }

                    final subtitleParts = <String>[
                      email,
                      role,
                      if (branchLabel.isNotEmpty) branchLabel,
                    ];

                    final isCurrentUser =
                        currentUser != null && d.id == currentUser.uid;

                    return ListTile(
                      title: Text(
                        name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        subtitleParts.join(' • '),
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrentUser)
                            const Text(
                              'You',
                              style: TextStyle(color: Colors.white54),
                            ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'View / Edit user',
                            onPressed: () async {
                              await showDialog(
                                context: context,
                                builder: (_) => _EditUserDialog(
                                  userId: d.id,
                                  initialData: data,
                                ),
                              );
                            },
                            icon: const Icon(Icons.manage_accounts,
                                color: Colors.white70),
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

class _RoleHelpNote extends StatelessWidget {
  const _RoleHelpNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Default roles',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '• Manager – access to bookings, live sessions, inventory (adjust/import), reports export, invoices, multi-branch.',
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 4),
          Text(
            '• Staff – access to bookings & live sessions (edit), inventory usage (no adjust/import), view reports/invoices, single branch.',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/* =========================== CREATE USER =========================== */

class _CreateUserResult {
  final String userId;
  final String email;
  final String role;
  final String? tempPassword;
  _CreateUserResult({
    required this.userId,
    required this.email,
    required this.role,
    this.tempPassword,
  });
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _role = 'staff';
  final List<String> _selectedBranches = [];
  bool _saving = false;
  String? _error;

  // allow both admin & superadmin to set temp password (UI only)
  bool _canSetTempPwd = false;

  // Always use the region you deployed to
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  void initState() {
    super.initState();
    _loadCurrentUserRole();
  }

  Future<void> _loadCurrentUserRole() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final role = snap.data()?['role']?.toString();
      setState(() {
        _canSetTempPwd = (role == 'superadmin' || role == 'admin');
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Create Console User',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: _darkInput('Name'),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailCtrl,
                decoration: _darkInput('Email'),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              if (_canSetTempPwd) ...[
                TextField(
                  controller: _passwordCtrl,
                  decoration: _darkInput('Password (optional - auto-generated if left empty)'),
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                value: _role,
                dropdownColor: const Color(0xFF111827),
                decoration: _darkInput('Role'),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(
                      value: 'superadmin', child: Text('Super Admin')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _role = v;
                      if (_role == 'staff' && _selectedBranches.length > 1) {
                        _selectedBranches
                          ..clear()
                          ..add(_selectedBranches.first);
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('branches')
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final branches = snap.data!.docs;
                    return Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: branches.map((b) {
                        final id = b.id;
                        final name =
                            (b.data() as Map<String, dynamic>? ?? {})['name']
                                    ?.toString() ??
                                id;
                        final selected = _selectedBranches.contains(id);
                        return FilterChip(
                          selected: selected,
                          label: Text(
                            name,
                            style: TextStyle(
                              color: selected ? Colors.black : Colors.white,
                            ),
                          ),
                          selectedColor: Colors.white,
                          backgroundColor: const Color(0xFF0F172A),
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                if (_role == 'staff') {
                                  _selectedBranches
                                    ..clear()
                                    ..add(id);
                                } else {
                                  if (!_selectedBranches.contains(id)) {
                                    _selectedBranches.add(id);
                                  }
                                }
                              } else {
                                _selectedBranches.remove(id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: _saving ? null : _create,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : const Text('Create User'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _darkInput(String label) {
    return const InputDecoration().copyWith(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (name.isEmpty || email.isEmpty) {
      setState(() => _error = 'Name and Email are required');
      return;
    }
    if (_selectedBranches.isEmpty) {
      setState(() => _error = 'Please select at least one branch');
      return;
    }
    if (_role == 'staff' && _selectedBranches.length > 1) {
      setState(() => _error = 'Staff can be linked to only one branch.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final payload = <String, dynamic>{
      'name': name,
      'email': email,
      'role': _role,
      'branchIds': _selectedBranches,
      if (_canSetTempPwd && password.isNotEmpty) 'tempPassword': password,
    };

    try {
      // IMPORTANT: asia-south1
      final callable = _functions.httpsCallable('createConsoleUser');
      final res = await callable.call(payload);
      final data = (res.data as Map?) ?? {};
      
      final uid = data['uid']?.toString() ?? '';
      
      if (!mounted) return;

      Navigator.of(context).pop(
        _CreateUserResult(
          userId: uid,
          email: email,
          role: _role,
          tempPassword: data['tempPassword']?.toString(),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      // map common errors to friendly messages
      String msg = e.message ?? 'Failed to create user.';
      if (e.code == 'permission-denied') {
        msg =
            'You do not have permission to create users. Only Admin/Superadmin.';
      } else if (e.code == 'already-exists') {
        msg = 'A user with this email already exists.';
      } else if (e.code == 'invalid-argument') {
        msg = 'Invalid input. Please check fields and try again.';
      }
      if (mounted) setState(() => _error = msg);
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to create user: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/* =========================== EDIT USER =========================== */

class _EditUserDialog extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> initialData;

  const _EditUserDialog({
    required this.userId,
    required this.initialData,
  });

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _passwordCtrl;
  late List<String> _selectedBranches;
  late String _role;
  bool _saving = false;
  String? _error;

  // Permissions
  final Map<String, bool> _permissions = {
    'viewBookings': false,
    'manageBookings': false,
    'viewInventory': false,
    'manageInventory': false,
    'cashInCounter': false,
    'viewAllBranches': false,
  };

  // region
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;

    _nameCtrl = TextEditingController(text: (d['name'] ?? '').toString());
    _emailCtrl = TextEditingController(text: (d['email'] ?? '').toString());
    _passwordCtrl = TextEditingController();

    _role = (d['role'] ?? 'staff').toString();
    _selectedBranches =
        (d['branchIds'] as List?)?.cast<String>() ?? <String>[];

    // Load existing permissions
    final existingPerms = d['permissions'] as Map<String, dynamic>?;
    if (existingPerms != null) {
      _permissions.forEach((key, _) {
        if (existingPerms.containsKey(key)) {
          _permissions[key] = existingPerms[key] == true;
        }
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'User Details',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  decoration: _darkInput('Name'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailCtrl,
                  enabled: false,
                  decoration: _darkInput('Email (from Auth)'),
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _role,
                  dropdownColor: const Color(0xFF111827),
                  decoration: _darkInput('Role'),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'staff', child: Text('Staff')),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                        value: 'superadmin', child: Text('Super Admin')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _role = v;
                      if (_role == 'staff' && _selectedBranches.length > 1) {
                        _selectedBranches
                          ..clear()
                          ..add(_selectedBranches.first);
                      }
                    });
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('branches')
                        .orderBy('name')
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      final branches = snap.data!.docs;
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: branches.map((b) {
                          final id = b.id;
                          final name =
                              (b.data() as Map<String, dynamic>? ?? {})['name']
                                      ?.toString() ??
                                  id;
                          final selected = _selectedBranches.contains(id);
                          return FilterChip(
                            selected: selected,
                            label: Text(
                              name,
                              style: TextStyle(
                                color: selected ? Colors.black : Colors.white,
                              ),
                            ),
                            selectedColor: Colors.white,
                            backgroundColor: const Color(0xFF0F172A),
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  if (_role == 'staff') {
                                    _selectedBranches
                                      ..clear()
                                      ..add(id);
                                  } else {
                                    if (!_selectedBranches.contains(id)) {
                                      _selectedBranches.add(id);
                                    }
                                  }
                                } else {
                                  _selectedBranches.remove(id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  decoration: _darkInput('New password (optional - leave blank to keep current)'),
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Permissions',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _permissionToggle('View Bookings', 'viewBookings'),
                      _permissionToggle('Manage Bookings', 'manageBookings'),
                      const Divider(color: Colors.white24),
                      _permissionToggle('View Inventory', 'viewInventory'),
                      _permissionToggle('Manage Inventory', 'manageInventory'),
                      const Divider(color: Colors.white24),
                      _permissionToggle('Cash in Counter', 'cashInCounter'),
                      _permissionToggle('View All Branches', 'viewAllBranches'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const CircularProgressIndicator()
                              : const Text('Save changes'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _darkInput(String label) {
    return const InputDecoration().copyWith(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white),
      ),
    );
  }

  Widget _permissionToggle(String label, String key) {
    return SwitchListTile(
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      value: _permissions[key] ?? false,
      onChanged: (v) {
        setState(() => _permissions[key] = v);
      },
      activeColor: Colors.white,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    if (_role == 'staff' && _selectedBranches.length > 1) {
      setState(() => _error = 'Staff can be linked to only one branch.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final newPwd = _passwordCtrl.text.trim();

    final update = <String, dynamic>{
      'name': name,
      'role': _role,
      'branchIds': _selectedBranches,
      'permissions': _permissions,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(update);

      // If admin provided a new password, update it via Cloud Function
      if (newPwd.isNotEmpty) {
        try {
          await _functions
              .httpsCallable('adminSetTempPassword')
              .call({'uid': widget.userId, 'tempPassword': newPwd});
        } catch (_) {
          // swallow; Firestore still updated
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to update user: $e';
      });
    }
  }
}

/* ===================== TEMP PASSWORD DISPLAY DIALOG ===================== */

class _TempPasswordDialog extends StatelessWidget {
  final String email;
  final String password;
  const _TempPasswordDialog({required this.email, required this.password});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1F2937),
      title: const Text('User Created',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Share these credentials with the user:',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          SelectableText('Email: $email',
              style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText('Temp Password: $password',
                    style: const TextStyle(color: Colors.white)),
              ),
              IconButton(
                tooltip: 'Copy password',
                icon: const Icon(Icons.copy, color: Colors.white70),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: password));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password copied')),
                  );
                },
              )
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'User will be forced to change password on first login.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        )
      ],
    );
  }
}

/* ===================== PERMISSIONS DIALOG ===================== */

class _PermissionsDialog extends StatefulWidget {
  final String userId;
  final String userRole;

  const _PermissionsDialog({
    required this.userId,
    required this.userRole,
  });

  @override
  State<_PermissionsDialog> createState() => _PermissionsDialogState();
}

class _PermissionsDialogState extends State<_PermissionsDialog> {
  final Map<String, bool> _permissions = {
    'viewBookings': false,
    'manageBookings': false,
    'viewInventory': false,
    'manageInventory': false,
    'cashInCounter': false,
    'viewAllBranches': false,
  };

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _setDefaultPermissions();
  }

  void _setDefaultPermissions() {
    switch (widget.userRole) {
      case 'superadmin':
      case 'admin':
        _permissions['viewBookings'] = true;
        _permissions['manageBookings'] = true;
        _permissions['viewInventory'] = true;
        _permissions['manageInventory'] = true;
        _permissions['cashInCounter'] = true;
        _permissions['viewAllBranches'] = true;
        break;
      case 'manager':
        _permissions['viewBookings'] = true;
        _permissions['manageBookings'] = true;
        _permissions['viewInventory'] = true;
        _permissions['manageInventory'] = true;
        _permissions['cashInCounter'] = false;
        _permissions['viewAllBranches'] = false;
        break;
      case 'staff':
        _permissions['viewBookings'] = true;
        _permissions['manageBookings'] = false;
        _permissions['viewInventory'] = true;
        _permissions['manageInventory'] = false;
        _permissions['cashInCounter'] = false;
        _permissions['viewAllBranches'] = false;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set User Permissions',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Configure permissions for this ${widget.userRole} user',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _permissionToggle('View Bookings', 'viewBookings'),
                  _permissionToggle('Manage Bookings', 'manageBookings'),
                  const Divider(color: Colors.white24),
                  _permissionToggle('View Inventory', 'viewInventory'),
                  _permissionToggle('Manage Inventory', 'manageInventory'),
                  const Divider(color: Colors.white24),
                  _permissionToggle('Cash in Counter', 'cashInCounter'),
                  _permissionToggle('View All Branches', 'viewAllBranches'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Save Permissions'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionToggle(String label, String key) {
    return SwitchListTile(
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      value: _permissions[key] ?? false,
      onChanged: (v) {
        setState(() => _permissions[key] = v);
      },
      activeColor: Colors.white,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({
        'permissions': _permissions,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save permissions: $e')),
      );
      setState(() => _saving = false);
    }
  }
}
