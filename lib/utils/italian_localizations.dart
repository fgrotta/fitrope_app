/// Localizzazioni di Flutter solo in italiano.
///
/// I delegate `GlobalMaterialLocalizations.delegate` & co. scelgono la
/// traduzione da una mappa con tutte le ~80 lingue supportate e registrano i
/// dati di date di tutte: dart2js non può scartarle e finiscono in
/// main.dart.js (~300 KB raw, ~76 KB brotli, circa l'11%). Questi delegate
/// costruiscono direttamente le classi italiane generate da
/// flutter_localizations (`MaterialLocalizationIt`, `CupertinoLocalizationIt`,
/// `WidgetsLocalizationIt`) con i formati di `intl` per `it`, che
/// `initializeItalianDateFormatting` ha già registrato. L'app ha la locale
/// fissata a `it_IT` (`MaterialApp.locale`).
///
/// Aggiungere una lingua significa aggiungere qui il suo delegate e i suoi dati
/// di date, non tornare ai delegate Global*: un test in
/// `test/italian_localizations_test.dart` lo impedisce.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

class _ItMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _ItMaterialDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'it';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(MaterialLocalizationIt(
        fullYearFormat: intl.DateFormat.y('it'),
        compactDateFormat: intl.DateFormat.yMd('it'),
        shortDateFormat: intl.DateFormat.yMMMd('it'),
        mediumDateFormat: intl.DateFormat.MMMEd('it'),
        longDateFormat: intl.DateFormat.yMMMMEEEEd('it'),
        yearMonthFormat: intl.DateFormat.yMMMM('it'),
        shortMonthDayFormat: intl.DateFormat.MMMd('it'),
        decimalFormat: intl.NumberFormat.decimalPattern('it'),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', 'it'),
      ));
  @override
  bool shouldReload(_ItMaterialDelegate old) => false;
}

class _ItCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _ItCupertinoDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'it';
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(CupertinoLocalizationIt(
        fullYearFormat: intl.DateFormat.y('it'),
        dayFormat: intl.DateFormat.d('it'),
        weekdayFormat: intl.DateFormat.E('it'),
        mediumDateFormat: intl.DateFormat.MMMEd('it'),
        singleDigitHourFormat: intl.DateFormat('HH', 'it'),
        singleDigitMinuteFormat: intl.DateFormat.m('it'),
        doubleDigitMinuteFormat: intl.DateFormat('mm', 'it'),
        singleDigitSecondFormat: intl.DateFormat.s('it'),
        decimalFormat: intl.NumberFormat.decimalPattern('it'),
      ));
  @override
  bool shouldReload(_ItCupertinoDelegate old) => false;
}

class _ItWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const _ItWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'it';
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<WidgetsLocalizations>(const WidgetsLocalizationIt());
  @override
  bool shouldReload(_ItWidgetsDelegate old) => false;
}

/// Da passare a `MaterialApp.localizationsDelegates`.
const List<LocalizationsDelegate<dynamic>> italianLocalizationsDelegates = [
  _ItMaterialDelegate(),
  _ItWidgetsDelegate(),
  _ItCupertinoDelegate(),
];
