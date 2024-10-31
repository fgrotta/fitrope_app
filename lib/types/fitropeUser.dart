import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/types/course.dart';

class FitropeUser {
  final String uid;
  final String name;
  final String lastName;
  final List<Course> courses;
  final TipologiaIscrizione? tipologiaIscrizione;
  final int? entrateDisponibili;
  final Timestamp? inizioIscrizione;
  final Timestamp? fineIscrizione;

  const FitropeUser({
    required this.name, 
    required this.lastName, 
    required this.uid, 
    required this.courses, 
    this.tipologiaIscrizione, 
    this.entrateDisponibili,
    this.inizioIscrizione, 
    this.fineIscrizione
  });
}

enum TipologiaIscrizione {
  PACCHETTO_ENTRATE,
  ABBONAMENTO
}