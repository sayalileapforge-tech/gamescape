import 'package:cloud_firestore/cloud_firestore.dart';

/// Persists the user’s dashboard section order in:
/// users/{uid}/preferences.dashboardOrder = [ "stats", "quick_actions", ... ]
class DashboardPrefsService {
  final String userId;
  DashboardPrefsService(this.userId);

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(userId);

  Future<List<String>?> loadOrder() async {
    final snap = await _userDoc.get();
    final data = snap.data();
    if (data == null) return null;
    final prefs = (data['preferences'] as Map?) ?? {};
    final list = prefs['dashboardOrder'];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return null;
    }

  Future<void> saveOrder(List<String> order) async {
    await _userDoc.set({
      'preferences': {
        'dashboardOrder': order,
      }
    }, SetOptions(merge: true));
  }
}
