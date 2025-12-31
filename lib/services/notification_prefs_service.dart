import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationPrefs {
  final bool newBookings;
  final bool overdue;
  final bool upcoming;
  final int upcomingWindowMins;
  final bool lowStock;
  final int lowStockThreshold; // 0 => use item.reorderThreshold
  final bool pendingDues;
  final bool endingSoon;
  final int endingSoonWindowMins;

  const NotificationPrefs({
    this.newBookings = true,
    this.overdue = true,
    this.upcoming = true,
    this.upcomingWindowMins = 60,
    this.lowStock = true,
    this.lowStockThreshold = 0,
    this.pendingDues = true,
    this.endingSoon = true,
    this.endingSoonWindowMins = 10,
  });

  NotificationPrefs copyWith({
    bool? newBookings,
    bool? overdue,
    bool? upcoming,
    int? upcomingWindowMins,
    bool? lowStock,
    int? lowStockThreshold,
    bool? pendingDues,
    bool? endingSoon,
    int? endingSoonWindowMins,
  }) {
    return NotificationPrefs(
      newBookings: newBookings ?? this.newBookings,
      overdue: overdue ?? this.overdue,
      upcoming: upcoming ?? this.upcoming,
      upcomingWindowMins: upcomingWindowMins ?? this.upcomingWindowMins,
      lowStock: lowStock ?? this.lowStock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      pendingDues: pendingDues ?? this.pendingDues,
      endingSoon: endingSoon ?? this.endingSoon,
      endingSoonWindowMins: endingSoonWindowMins ?? this.endingSoonWindowMins,
    );
  }

  Map<String, dynamic> toMap() => {
        'newBookings': newBookings,
        'overdue': overdue,
        'upcoming': upcoming,
        'upcomingWindowMins': upcomingWindowMins,
        'lowStock': lowStock,
        'lowStockThreshold': lowStockThreshold,
        'pendingDues': pendingDues,
        'endingSoon': endingSoon,
        'endingSoonWindowMins': endingSoonWindowMins,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static NotificationPrefs fromMap(Map<String, dynamic>? m) {
    final map = m ?? {};
    return NotificationPrefs(
      newBookings: (map['newBookings'] ?? true) == true,
      overdue: (map['overdue'] ?? true) == true,
      upcoming: (map['upcoming'] ?? true) == true,
      upcomingWindowMins: (map['upcomingWindowMins'] as num?)?.toInt() ?? 60,
      lowStock: (map['lowStock'] ?? true) == true,
      lowStockThreshold: (map['lowStockThreshold'] as num?)?.toInt() ?? 0,
      pendingDues: (map['pendingDues'] ?? true) == true,
      endingSoon: (map['endingSoon'] ?? true) == true,
      endingSoonWindowMins: (map['endingSoonWindowMins'] as num?)?.toInt() ?? 10,
    );
  }
}

class NotificationPrefsService {
  static DocumentReference<Map<String, dynamic>> _docRef(String userId) =>
      FirebaseFirestore.instance.collection('users').doc(userId).collection('meta').doc('notification_prefs');

  static Stream<NotificationPrefs> stream(String userId) {
    return _docRef(userId).snapshots().map((d) => NotificationPrefs.fromMap(d.data()));
  }

  static Future<void> save(String userId, NotificationPrefs prefs) async {
    await _docRef(userId).set(prefs.toMap(), SetOptions(merge: true));
  }
}
