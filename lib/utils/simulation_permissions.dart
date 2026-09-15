import 'package:fitrope_app/types/fitrope_user.dart';

/// Perimetro della modalità simulazione, in un unico predicato puro e testabile
/// (stile `lib/utils/course_filters.dart`).
///
/// Regole:
/// - solo un **Admin** può simulare, e solo utenti con `role == 'User'`
///   (niente Trainer, niente altri Admin);
/// - mai se stesso;
/// - niente annidamento ([alreadySimulating]).
///
/// Il perimetro è indipendente dal layout: la simulazione è disponibile a
/// qualunque larghezza, telefono compreso (la barra ha una variante compatta e
/// gli entry point mobile stanno nel menu ⋮ della lista utenti e nell'AppBar
/// del dettaglio).
bool canSimulateUser({
  required FitropeUser? actor,
  required FitropeUser target,
  required bool alreadySimulating,
}) {
  if (actor == null) return false;
  if (actor.role != 'Admin') return false;
  if (target.role != 'User') return false;
  if (actor.uid == target.uid) return false;
  if (alreadySimulating) return false;
  return true;
}
