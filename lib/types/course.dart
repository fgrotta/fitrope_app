import 'package:cloud_firestore/cloud_firestore.dart';

class Course {
  final int id;
  final int gymId;
  final String name;
  final Timestamp startDate;
  final Timestamp endDate;
  final int capacity;

  const Course({ required this.gymId, required this.name, required this.startDate, required this.endDate, required this.id, required this.capacity });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as int,
      gymId: json['gymId'] as int,
      name: json['name'] as String,
      startDate: json['startDate'] as Timestamp,
      endDate: json['endDate'] as Timestamp,
      capacity: json['capacity'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'gymId': gymId,
      'name': name,
      'startDate': startDate,
      'endDate': endDate,
      'capacity': capacity,
    };
  }
}