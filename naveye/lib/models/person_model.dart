class Person {
  final int? id;
  final String name;
  final String imagePath;
  final DateTime createdAt;

  Person({this.id, required this.name, required this.imagePath, required this.createdAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'],
      name: map['name'],
      imagePath: map['image_path'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
