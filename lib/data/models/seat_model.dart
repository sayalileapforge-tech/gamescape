class SeatModel {
  final String id;
  final String label;
  final String type; // e.g. "PC", "VIP", "Console"
  final num ratePerHour;
  final bool active;

  // Additive fields for richer pricing logic
  final num? rate30Single;
  final num? rate60Single;
  final num? rate30Multi;
  final num? rate60Multi;
  final bool supportsMultiplayer;

  SeatModel({
    required this.id,
    required this.label,
    required this.type,
    required this.ratePerHour,
    required this.active,
    this.rate30Single,
    this.rate60Single,
    this.rate30Multi,
    this.rate60Multi,
    this.supportsMultiplayer = false,
  });

  factory SeatModel.fromMap(String id, Map<String, dynamic> data) {
    return SeatModel(
      id: id,
      label: data['label'] ?? '',
      type: data['type'] ?? 'Standard',
      ratePerHour: data['ratePerHour'] ?? 0,
      active: data['active'] ?? true,
      rate30Single: data['rate30Single'],
      rate60Single: data['rate60Single'],
      rate30Multi: data['rate30Multi'],
      rate60Multi: data['rate60Multi'],
      supportsMultiplayer: data['supportsMultiplayer'] ??
          (data['rate30Multi'] != null || data['rate60Multi'] != null),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'type': type,
      'ratePerHour': ratePerHour,
      'active': active,
      if (rate30Single != null) 'rate30Single': rate30Single,
      if (rate60Single != null) 'rate60Single': rate60Single,
      if (rate30Multi != null) 'rate30Multi': rate30Multi,
      if (rate60Multi != null) 'rate60Multi': rate60Multi,
      'supportsMultiplayer': supportsMultiplayer,
    };
  }
}
