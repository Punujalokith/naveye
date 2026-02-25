import 'dart:convert';

class Person {
  final int? id;
  final String name;
  final String imagePath;
  final DateTime createdAt;
  final List<double> embedding; // face embedding vector

  Person({
    this.id,
    required this.name,
    required this.imagePath,
    required this.createdAt,
    this.embedding = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
      'embedding': embedding.isEmpty ? null : jsonEncode(embedding),
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    List<double> emb = [];
    if (map['embedding'] != null) {
      final decoded = jsonDecode(map['embedding'] as String) as List;
      emb = decoded.map((e) => (e as num).toDouble()).toList();
    }
    return Person(
      id: map['id'],
      name: map['name'],
      imagePath: map['image_path'],
      createdAt: DateTime.parse(map['created_at']),
      embedding: emb,
    );
  }
}
