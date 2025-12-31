import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/branch_model.dart';

class BranchRepo {
  final _col = FirebaseFirestore.instance.collection('branches');

  Stream<List<BranchModel>> watchBranches() {
    return _col.snapshots().map(
          (snap) => snap.docs
              .map((d) => BranchModel.fromMap(d.id, d.data()))
              .toList(),
        );
  }

  Future<List<BranchModel>> fetchBranches() async {
    final snap = await _col.get();
    return snap.docs
        .map((d) => BranchModel.fromMap(d.id, d.data()))
        .toList();
  }

  Future<void> addBranch(BranchModel branch) async {
    await _col.add(branch.toMap());
  }

  Future<void> updateBranch(BranchModel branch) async {
    await _col.doc(branch.id).update(branch.toMap());
  }

  Future<void> deleteBranch(String id) async {
    await _col.doc(id).delete();
  }
}
