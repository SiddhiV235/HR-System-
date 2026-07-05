/// A single registered face: an id, a display name, and the 192-d
/// embedding vector produced by the MobileFaceNet model.
class RegisteredFace {
  final String id;
  final String name;
  final List<double> embedding;
  final DateTime registeredAt;

  RegisteredFace({
    required this.id,
    required this.name,
    required this.embedding,
    DateTime? registeredAt,
  }) : registeredAt = registeredAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'embedding': embedding,
        'registeredAt': registeredAt.toIso8601String(),
      };

  factory RegisteredFace.fromJson(Map<String, dynamic> json) {
    return RegisteredFace(
      id: json['id'] as String,
      name: json['name'] as String,
      embedding: (json['embedding'] as List)
          .map((e) => (e as num).toDouble())
          .toList(),
      registeredAt: json['registeredAt'] != null
          ? DateTime.tryParse(json['registeredAt'] as String)
          : null,
    );
  }
}
