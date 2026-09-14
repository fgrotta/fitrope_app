import 'package:fitrope_app/types/fitrope_user.dart';

/// Perimetro della modalità simulazione, in un unico predicato puro e testabile
/// (stile `lib/utils/course_filters.dart`).
///
/// Regole:
/// - solo un **Admin** può simulare, e solo utenti con `role == 'User'`
///   (niente Trainer, niente altri Admin);
/// - mai se stesso;
/// - niente annidamento ([alreadySimulating]);
/// - solo tablet e desktop ([isMobileLayout] false, cioè larghezza ≥ 600):
///   su mobile la barra + le azioni admin non stanno nello spazio disponibile.
///
/// Il gate sulla larghezza vale sull'**avvio**, non sulla permanenza: se la
/// finestra scende sotto 600 a simulazione attiva NON si esce (la guardia
/// read-only è indipendente dalla larghezza, e un'uscita automatica su un
/// resize sarebbe sconcertante).
bool canSimulateUser({
  required FitropeUser? actor,
  required FitropeUser target,
  required bool isMobileLayout,
  required bool alreadySimulating,
}) {
  if (actor == null) return false;
  if (actor.role != 'Admin') return false;
  if (target.role != 'User') return false;
  if (actor.uid == target.uid) return false;
  if (isMobileLayout) return false;
  if (alreadySimulating) return false;
  return true;
}
