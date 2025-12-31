import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// feature screens
import '../../features/auth/login_screen.dart';
import '../../features/auth/bootstrap_superadmin_screen.dart';
import '../../features/dashboard/admin_dashboard_screen.dart';
import '../../features/branches/branches_screen.dart';
import '../../features/bookings/bookings_screen.dart';
import '../../features/sessions/live_sessions_screen.dart';
import '../../features/customers/customers_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/inventory/inventory_logs_screen.dart';
import '../../features/inventory/inventory_unified_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/billing/invoices_screen.dart';
import '../../features/user/user_management_screen.dart';
import '../../features/tv_control/tv_control_screen.dart'; // ✅ TV Control
import '../../features/tv_control/tv_devices_screen.dart'; // ✅ TV Devices

/// Tiny cache to load Firestore user doc *outside* the redirect
class _UserDocCache {
  _UserDocCache._();
  static final _UserDocCache I = _UserDocCache._();

  Map<String, dynamic>? _data;
  String? _uidLoaded;
  bool _loading = false;

  Map<String, dynamic>? get data => _data;

  void ensureLoaded(String uid) {
    if (_loading) return;
    if (_uidLoaded == uid && _data != null) return;
    _loading = true;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .then((doc) {
      if (doc.exists) {
        _data = doc.data();
        _uidLoaded = uid;
      }
    }).whenComplete(() => _loading = false);
  }
}

class AppRouter {
  static final _rootKey = GlobalKey<NavigatorState>();

  static final router = GoRouter(
    navigatorKey: _rootKey,
    debugLogDiagnostics: true, // helpful to see redirect decisions
    initialLocation: '/login',
    routes: [
      GoRoute(
          path: '/login',
          name: 'login',
          builder: (c, s) => const LoginScreen()),
      GoRoute(
          path: '/bootstrap-admin',
          name: 'bootstrap-admin',
          builder: (c, s) => const BootstrapSuperAdminScreen()),

      GoRoute(
          path: '/dashboard',
          name: 'dashboard',
          builder: (c, s) => const AdminDashboardScreen()),
      GoRoute(
          path: '/branches',
          name: 'branches',
          builder: (c, s) => const BranchesScreen()),
      GoRoute(
          path: '/bookings',
          name: 'bookings',
          builder: (c, s) => const BookingsScreen()),
      GoRoute(
          path: '/live-sessions',
          name: 'live-sessions',
          builder: (c, s) => const LiveSessionsScreen()),
      GoRoute(
          path: '/customers',
          name: 'customers',
          builder: (c, s) => const CustomersScreen()),

      GoRoute(
          path: '/inventory',
          name: 'inventory',
          builder: (c, s) => const InventoryScreen()),
      GoRoute(
          path: '/inventory-logs',
          name: 'inventory-logs',
          builder: (c, s) => const InventoryLogsScreen()),
      GoRoute(
          path: '/inventory-unified',
          name: 'inventory-unified',
          builder: (c, s) => const InventoryUnifiedScreen()),

      GoRoute(
          path: '/reports',
          name: 'reports',
          builder: (c, s) => const ReportsScreen()),
      GoRoute(
          path: '/invoices',
          name: 'invoices',
          builder: (c, s) => const InvoicesScreen()),
      GoRoute(
          path: '/users',
          name: 'users',
          builder: (c, s) => const UserManagementScreen()),

      // ✅ TV Control screen route
      GoRoute(
          path: '/tv-control',
          name: 'tv-control',
          builder: (c, s) => const TvControlScreen()),

      // ✅ TV Devices manager screen route
      GoRoute(
          path: '/tv-devices',
          name: 'tv-devices',
          builder: (c, s) => const TvDevicesScreen()),
    ],
    redirect: (context, state) {
      // Use PATH ONLY to avoid loops due to query strings.
      final loc = state.uri.path; // e.g., '/login', '/dashboard'
      String? go(String target) => (loc == target) ? null : target;

      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;

      // 1) Not signed in → allow only /login and /bootstrap-admin
      if (user == null) {
        if (loc == '/login' || loc == '/bootstrap-admin') return null;
        return go('/login');
      }

      // 2) Signed in → preload user doc in background
      _UserDocCache.I.ensureLoaded(user.uid);

      // 3) If already signed in, keep them out of auth screens
      if (loc == '/login' || loc == '/bootstrap-admin') {
        return go('/dashboard');
      }

      // 4) Role-based gates (staff restrictions)
      final data = _UserDocCache.I.data;
      if (data != null) {
        final role = (data['role'] ?? 'staff').toString();
        final isStaff = role == 'staff';
        const adminOnly = <String>{
          '/branches',
          '/reports',
          '/users',
          '/invoices',
          '/inventory',
          '/inventory-logs',
          '/inventory-unified',
          '/tv-control', // ✅ TV control is admin/manager only
          '/tv-devices', // ✅ TV devices manager is admin/manager only
        };
        if (isStaff && adminOnly.contains(loc)) return go('/dashboard');
      }

      // No redirect
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Text(
          'Route error: ${state.error}',
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}
