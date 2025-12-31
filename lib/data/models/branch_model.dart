class BranchModel {
  final String id;
  final String name;
  final String? address;
  final bool active;

  BranchModel({
    required this.id,
    required this.name,
    this.address,
    required this.active,
  });

  factory BranchModel.fromMap(String id, Map<String, dynamic> data) {
    return BranchModel(
      id: id,
      name: data['name'] ?? '',
      address: data['address'],
      active: data['active'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'active': active,
    };
  }
}
