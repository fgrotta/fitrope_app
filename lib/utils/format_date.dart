String formatDate(DateTime? dateTime) {
  if(dateTime == null) {
    return '';
  }

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