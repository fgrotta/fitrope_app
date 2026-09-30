import 'package:fitrope_app/pages/protected/guide/guide_catalog.dart';
import 'package:fitrope_app/pages/protected/guide/guide_index_page.dart';
import 'package:fitrope_app/pages/protected/guide/guide_page.dart';
import 'package:flutter/widgets.dart';

/// Punto d'ingresso della route `/guida`, caricato in modo differito dal
/// router. Con un [id] valido apre direttamente quella guida (per i link
/// contestuali "?" dalle pagine), altrimenti l'indice.
Widget buildGuideRoute({String? id}) {
  final entry = id == null ? null : guideById(id);
  if (entry != null) return GuidePage(entry: entry);
  return const GuideIndexPage();
}
