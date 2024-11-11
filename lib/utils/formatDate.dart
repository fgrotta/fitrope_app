String formatDate(DateTime dateTime) {
  final months = [
    'Gennaio',
    'Febbraio',
    'Marzo',
    'Aprile',
    'Maggio',
    'Giugno',
    'Luglio',
    'Agosto',
    'Settembre',
    'Ottobre',
    'Novembre',
    'Dicembre',
  ];

  return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}';
}