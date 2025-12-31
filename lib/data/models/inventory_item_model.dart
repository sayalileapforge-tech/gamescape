class InventoryItemModel {
  final String id;
  final String name;
  final num price;
  final num stockQty;
  final String? sku;
  final bool active;

  /// When stockQty <= reorderThreshold → item is treated as "Low stock"
  final num reorderThreshold;

  InventoryItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.stockQty,
    this.sku,
    required this.active,
    this.reorderThreshold = 0,
  });

  static num _numOrZero(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v) ?? 0;
    return 0;
  }

  factory InventoryItemModel.fromMap(String id, Map<String, dynamic> data) {
    return InventoryItemModel(
      id: id,
      name: data['name'] ?? '',
      price: _numOrZero(data['price']),
      stockQty: _numOrZero(data['stockQty']),
      sku: data['sku'],
      active: data['active'] ?? true,
      reorderThreshold: _numOrZero(data['reorderThreshold']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'stockQty': stockQty,
      'sku': sku,
      'active': active,
      'reorderThreshold': reorderThreshold,
    };
  }
}
