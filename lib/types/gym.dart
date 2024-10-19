class Gym {
  final int id;
  final String name;

  const Gym({ required this.id, required this.name });

  factory Gym.fromJson(Map<String, dynamic> json) {
    return Gym(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}