import 'package:cloud_functions/cloud_functions.dart';

class AdminUserService {
  final _functions = FirebaseFunctions.instance;

  Future<Map<String, dynamic>> createConsoleUser({
    required String email,
    required String name,
    required String role,
    required List<String> branchIds,
  }) async {
    final callable = _functions.httpsCallable('createConsoleUser');
    final result = await callable.call({
      'email': email,
      'name': name,
      'role': role,
      'branchIds': branchIds,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }
}
