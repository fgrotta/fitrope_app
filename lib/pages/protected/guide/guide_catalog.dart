import 'package:flutter/material.dart';

/// Sezioni dell'indice della Guida Admin, nell'ordine in cui compaiono.
enum GuideCategory {
  utenti('Utenti'),
  abbonamenti('Abbonamenti e ingressi'),
  corsi('Corsi e iscrizioni'),
  panoramica('Home e Dashboard'),
  problemi('Risoluzione problemi');

  const GuideCategory(this.label);

  final String label;
}

/// Una guida: un file Markdown in `assets/guida/<id>.md`, le sue immagini in
/// `assets/guida/img/<id>/` e lo scenario che le rigenera in
/// `tool/guida/scenarios/<id>.mjs`. Lo stesso id tiene insieme i tre pezzi
/// (lo verifica `test/guide_catalog_test.dart`).
class GuideEntry {
  final String id;
  final String title;
  final String summary;
  final GuideCategory category;
  final IconData icon;

  const GuideEntry({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.icon,
  });

  String get asset => 'assets/guida/$id.md';
}

const List<GuideEntry> guideCatalog = [
  GuideEntry(
    id: 'registrazione-utente',
    title: 'Registrare un nuovo utente',
    summary: 'Crea Utente con o senza email, piano iniziale, registrazione '
        'autonoma del socio e Prova al primo accesso',
    category: GuideCategory.utenti,
    icon: Icons.person_add_alt_1,
  ),
  GuideEntry(
    id: 'gestione-utente',
    title: 'Gestire un utente',
    summary: 'Anagrafica, ruolo, certificato medico, disattivazione, reset '
        'password ed email mancante',
    category: GuideCategory.utenti,
    icon: Icons.manage_accounts,
  ),
  GuideEntry(
    id: 'simula-utente',
    title: 'Vedere l\'app come un socio',
    summary: 'Simula utente per capire cosa vede un socio, in sola lettura',
    category: GuideCategory.utenti,
    icon: Icons.visibility_outlined,
  ),
  GuideEntry(
    id: 'abbonamenti',
    title: 'Assegnare, modificare e revocare un abbonamento',
    summary: 'Assegna abbonamento, Modifica, Revoca e sostituzione della Prova',
    category: GuideCategory.abbonamenti,
    icon: Icons.card_membership,
  ),
  GuideEntry(
    id: 'pacchetti-ingressi',
    title: 'Pacchetti a ingressi',
    summary: 'Ingressi residui, pacchetto esaurito e finestra di disdetta',
    category: GuideCategory.abbonamenti,
    icon: Icons.confirmation_number_outlined,
  ),
  GuideEntry(
    id: 'migrazione-utente-legacy',
    title: 'Migrare un utente dal vecchio abbonamento',
    summary: 'Normalizza profilo, migrazione automatica o con piano scelto',
    category: GuideCategory.abbonamenti,
    icon: Icons.move_up,
  ),
  GuideEntry(
    id: 'corsi',
    title: 'Creare e gestire i corsi',
    summary: 'Nuovo corso, modifica, duplica, corsi ricorrenti ed eliminazione',
    category: GuideCategory.corsi,
    icon: Icons.event,
  ),
  GuideEntry(
    id: 'iscrivere-socio-a-corso',
    title: 'Iscrivere o rimuovere un socio da un corso',
    summary: 'Aggiungi iscritto, Rimuovi iscrizione e lista d\'attesa',
    category: GuideCategory.corsi,
    icon: Icons.how_to_reg,
  ),
  GuideEntry(
    id: 'correggi-conteggio',
    title: 'Correggere il conteggio degli iscritti',
    summary: 'Quando il numero di iscritti di un corso non torna',
    category: GuideCategory.corsi,
    icon: Icons.sync_problem,
  ),
  GuideEntry(
    id: 'home-e-dashboard',
    title: 'Home e Dashboard',
    summary: 'Scadenze, lezioni di prova, regolamento, statistiche ed '
        'esportazione CSV',
    category: GuideCategory.panoramica,
    icon: Icons.dashboard_outlined,
  ),
  GuideEntry(
    id: 'problemi-app',
    title: 'Problemi frequenti',
    summary: 'App che non si aggiorna, notifiche, email in spam, socio che '
        'non riesce a iscriversi',
    category: GuideCategory.problemi,
    icon: Icons.build_outlined,
  ),
];

GuideEntry? guideById(String id, [List<GuideEntry> catalog = guideCatalog]) {
  for (final entry in catalog) {
    if (entry.id == id) return entry;
  }
  return null;
}
