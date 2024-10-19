import 'package:fitrope_app/types/gym.dart';

class Course {
  final int id;
  final Gym gym;
  final String name;
  final String startDate;
  final String endDate;
  final int capacity;

  const Course({ required this.gym, required this.name, required this.startDate, required this.endDate, required this.id, required this.capacity });
}