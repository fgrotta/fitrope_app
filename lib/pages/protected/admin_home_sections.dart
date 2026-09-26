import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/api/authentication/get_users_with_expiring_certificates.dart';
import 'package:fitrope_app/api/authentication/get_users_with_expiring_subscriptions.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/pages/protected/user_detail_page.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/abbonamento_helper.dart';
import 'package:fitrope_app/utils/certificato_helper.dart';
import 'package:fitrope_app/utils/get_tipologia_iscrizione_label.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Letture delle sezioni admin della Home, iniettabili per i test.
class AdminHomeLoaders {
  final Future<List<FitropeUser>> Function() expiringCertificates;
  final Future<List<FitropeUser>> Function() expiringSubscriptions;
  final Future<List<FitropeUser>> Function() allUsers;

  const AdminHomeLoaders({
    required this.expiringCertificates,
    required this.expiringSubscriptions,
    required this.allUsers,
  });

  static const AdminHomeLoaders firestore = AdminHomeLoaders(
    expiringCertificates: getUsersWithExpiringCertificates,
    expiringSubscriptions: getUsersWithExpiringSubscriptions,
    allUsers: getUsers,
  );
}

/// Sezioni della Home riservate agli Admin: certificati e abbonamenti in
/// scadenza, lezioni di prova, regolamento non accettato.
///
/// Vive in una libreria a parte perché `HomePage` la importa con
/// `deferred as`: nella build dart2js un socio non scarica questo codice.
/// `HomePage` la costruisce solo per `role == 'Admin'`, quindi qui dentro non
/// si ricontrolla il ruolo.
///
/// Refresh: le quattro letture si agganciano a `RefreshManager` (resume,
/// mutazioni utente) con [RefreshListenersMixin], che le toglie tutte in
/// dispose. [refreshSignal] è il segnale della Home dopo un'iscrizione o una
/// disiscrizione dell'admin stesso: rilegge certificati e abbonamenti, come
/// faceva `refreshCourses`. È un `Listenable` e non una GlobalKey perché i
/// tipi di una libreria deferred non si possono nominare da `HomePage`.
class AdminHomeSections extends StatefulWidget {
  final List<Course> allCourses;
  final Listenable refreshSignal;

  @visibleForTesting
  final AdminHomeLoaders? loaders;

  const AdminHomeSections({
    super.key,
    required this.allCourses,
    required this.refreshSignal,
    this.loaders,
  });

  @override
  State<AdminHomeSections> createState() => _AdminHomeSectionsState();
}

class _AdminHomeSectionsState extends State<AdminHomeSections>
    with RefreshListenersMixin<AdminHomeSections> {
  List<FitropeUser> utentiConCertificatoInScadenza = [];
  bool isLoadingCertificati = false;
  List<FitropeUser> utentiConAbbonamentoInScadenza = [];
  bool isLoadingAbbonamenti = false;
  List<FitropeUser> _utentiProva = [];
  bool _isLoadingLezioniProva = false;
  bool _scadenzeExpanded = true;
  bool _lezioniProvaExpanded = true;
  bool _regolamentoExpanded = true;
  List<FitropeUser> _utentiSenzaRegolamento = [];
  bool _isLoadingRegolamento = false;

  AdminHomeLoaders get _loaders => widget.loaders ?? AdminHomeLoaders.firestore;

  @override
  void initState() {
    super.initState();
    _loadUtentiConCertificatoInScadenza();
    _loadUtentiConAbbonamentoInScadenza();
    _loadUtentiLezioneProva();
    _loadUtentiSenzaRegolamento();

    listenToRefresh(_loadUtentiConCertificatoInScadenza);
    listenToRefresh(_loadUtentiConAbbonamentoInScadenza);
    listenToRefresh(_loadUtentiLezioneProva);
    listenToRefresh(_loadUtentiSenzaRegolamento);
    widget.refreshSignal.addListener(_onHomeRefresh);
  }

  @override
  void didUpdateWidget(AdminHomeSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      oldWidget.refreshSignal.removeListener(_onHomeRefresh);
      widget.refreshSignal.addListener(_onHomeRefresh);
    }
  }

  @override
  void dispose() {
    widget.refreshSignal.removeListener(_onHomeRefresh);
    super.dispose();
  }

  void _onHomeRefresh() {
    _loadUtentiConCertificatoInScadenza();
    _loadUtentiConAbbonamentoInScadenza();
  }

  // Funzione ottimizzata per caricare solo gli utenti con certificati in scadenza
  Future<void> _loadUtentiConCertificatoInScadenza() async {
    if (!mounted) return;

    setState(() {
      isLoadingCertificati = true;
    });

    try {
      final utenti = await _loaders.expiringCertificates();
      if (!mounted) return;

      setState(() {
        utentiConCertificatoInScadenza = utenti;
        isLoadingCertificati = false;
      });
    } catch (e) {
      debugPrint(
        'Errore nel caricamento utenti con certificati in scadenza: $e',
      );
      if (!mounted) return;
      setState(() {
        isLoadingCertificati = false;
      });
    }
  }

  // Funzione ottimizzata per caricare solo gli utenti con abbonamenti in scadenza
  Future<void> _loadUtentiConAbbonamentoInScadenza() async {
    if (!mounted) return;

    setState(() {
      isLoadingAbbonamenti = true;
    });

    try {
      final utenti = await _loaders.expiringSubscriptions();
      if (!mounted) return;

      setState(() {
        utentiConAbbonamentoInScadenza = utenti;
        isLoadingAbbonamenti = false;
      });
    } catch (e) {
      debugPrint(
        'Errore nel caricamento utenti con abbonamenti in scadenza: $e',
      );
      if (!mounted) return;
      setState(() {
        isLoadingAbbonamenti = false;
      });
    }
  }

  Future<void> _loadUtentiLezioneProva() async {
    if (!mounted) return;
    setState(() {
      _isLoadingLezioniProva = true;
    });
    try {
      final utenti = await _loaders.allUsers();
      if (mounted) {
        setState(() {
          _utentiProva = utenti
              .where((u) => u.isTrialSubscriptionUser && u.isActive)
              .toList();
          _isLoadingLezioniProva = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingLezioniProva = false;
        });
      }
    }
  }

  Future<void> _loadUtentiSenzaRegolamento() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRegolamento = true;
    });
    try {
      final utenti = await _loaders.allUsers();
      if (mounted) {
        setState(() {
          _utentiSenzaRegolamento = utenti
              .where(
                (u) =>
                    u.regolamentoAccettatoIl == null &&
                    u.isActive &&
                    u.role == 'User',
              )
              .toList();
          _isLoadingRegolamento = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRegolamento = false;
        });
      }
    }
  }

  Widget _buildCertificatiInScadenzaCard() {
    if (isLoadingCertificati) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Flexible(child: Text('Caricamento certificati in scadenza...')),
          ],
        ),
      );
    }

    if (utentiConCertificatoInScadenza.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                'Certificati in Scadenza (${utentiConCertificatoInScadenza.length})',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...utentiConCertificatoInScadenza.map((utente) {
            final giorniRimanenti = CertificatoHelper.getGiorniRimanenti(
              utente.certificatoScadenza,
            );
            final dataScadenza = CertificatoHelper.formatDataScadenza(
              utente.certificatoScadenza,
            );

            return InkWell(
              onTap: () async {
                final updatedUser = await Navigator.push<FitropeUser>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailPage(user: utente),
                  ),
                );

                // Se l'utente è stato aggiornato, ricarica i certificati
                if (updatedUser != null) {
                  _loadUtentiConCertificatoInScadenza();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.red.shade100,
                      radius: 20,
                      child: Text(
                        '${utente.name.isNotEmpty ? utente.name[0] : ''}${utente.lastName.isNotEmpty ? utente.lastName[0] : ''}',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${utente.name} ${utente.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (giorniRimanenti >= 0)
                            Text(
                              'Scadenza: $dataScadenza',
                              style: TextStyle(
                                color: Colors.red.shade600,
                                fontSize: 14,
                              ),
                            )
                          else
                            Text(
                              'Scaduto il $dataScadenza',
                              style: TextStyle(
                                color: Colors.red.shade600,
                                fontSize: 14,
                              ),
                            ),
                          if (giorniRimanenti >= 0)
                            Text(
                              'Giorni rimanenti: $giorniRimanenti',
                              style: TextStyle(
                                color: giorniRimanenti <= 3
                                    ? Colors.red
                                    : Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.red.shade400,
                      size: 16,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAbbonamentiInScadenzaCard() {
    if (isLoadingAbbonamenti) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Flexible(child: Text('Caricamento abbonamenti in scadenza...')),
          ],
        ),
      );
    }

    if (utentiConAbbonamentoInScadenza.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop(context) ? 4 : 8,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                color: Colors.orange.shade700,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Abbonamenti in Scadenza (${utentiConAbbonamentoInScadenza.length})',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...utentiConAbbonamentoInScadenza.map((utente) {
            final giorniRimanenti = AbbonamentoHelper.getGiorniRimanenti(
              utente.fineIscrizione,
            );
            final dataScadenza = AbbonamentoHelper.formatDataScadenza(
              utente.fineIscrizione,
            );

            return InkWell(
              onTap: () async {
                final updatedUser = await Navigator.push<FitropeUser>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailPage(user: utente),
                  ),
                );

                // Se l'utente è stato aggiornato, ricarica gli abbonamenti
                if (updatedUser != null) {
                  _loadUtentiConAbbonamentoInScadenza();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      radius: 20,
                      child: Text(
                        '${utente.name.isNotEmpty ? utente.name[0] : ''}${utente.lastName.isNotEmpty ? utente.lastName[0] : ''}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${utente.name} ${utente.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Scadenza: $dataScadenza',
                            style: TextStyle(
                              color: Colors.orange.shade600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Abbonamento: ${getTipologiaIscrizioneLabel(utente.tipologiaIscrizione)}',
                            style: TextStyle(
                              color: Colors.orange.shade600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Giorni rimanenti: $giorniRimanenti',
                            style: TextStyle(
                              color: giorniRimanenti <= 3
                                  ? Colors.red
                                  : Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.orange.shade400,
                      size: 16,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLezioniProvaSection({
    required String title,
    required IconData icon,
    required Color bgColor,
    required Color borderColor,
    required Color headerColor,
    required Color avatarBgColor,
    required List<(FitropeUser, List<Course>)> entries,
  }) {
    final dateFmt = DateFormat('EEE dd/MM', 'it_IT');
    final timeFmt = DateFormat('HH:mm');

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop(context) ? 4 : 8,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: headerColor, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: headerColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...entries.map((entry) {
            final (utente, courses) = entry;
            return InkWell(
              onTap: () async {
                await Navigator.push<FitropeUser>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailPage(user: utente),
                  ),
                );
                _loadUtentiLezioneProva();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: avatarBgColor,
                      radius: 20,
                      child: Text(
                        '${utente.name.isNotEmpty ? utente.name[0] : ''}${utente.lastName.isNotEmpty ? utente.lastName[0] : ''}',
                        style: TextStyle(
                          color: headerColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${utente.name} ${utente.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            utente.email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: onSurfaceVariantColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...courses.map((c) {
                            final start = c.startDate.toDate();
                            final end = c.endDate.toDate();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.event,
                                    size: 14,
                                    color: headerColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: onSurfaceColor,
                                          ),
                                        ),
                                        Text(
                                          '${dateFmt.format(start)}  ${timeFmt.format(start)} – ${timeFmt.format(end)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: onSurfaceVariantColor,
                                          ),
                                        ),
                                        Text(
                                          'Posti: ${c.subscribed}/${c.capacity}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: onSurfaceVariantColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: borderColor, size: 16),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLezioniProvaProssimi7Giorni() {
    if (_isLoadingLezioniProva) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Flexible(child: Text('Caricamento lezioni di prova...')),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final limit = now.add(const Duration(days: 7));

    final entries = _utentiProva
        .map((u) {
          final courses = widget.allCourses
              .where(
                (c) =>
                    u.courses.contains(c.uid) &&
                    c.startDate.toDate().isAfter(now) &&
                    c.startDate.toDate().isBefore(limit),
              )
              .toList()
            ..sort(
              (a, b) => a.startDate.toDate().compareTo(b.startDate.toDate()),
            );
          return (u, courses);
        })
        .where((e) => e.$2.isNotEmpty)
        .toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return _buildLezioniProvaSection(
      title: 'Lezioni di prova – Prossimi 7 giorni (${entries.length})',
      icon: Icons.calendar_month,
      bgColor: Colors.blue.shade50,
      borderColor: Colors.blue.shade300,
      headerColor: Colors.blue.shade700,
      avatarBgColor: Colors.blue.shade100,
      entries: entries,
    );
  }

  Widget _buildLezioniProvaUltimi15Giorni() {
    if (_isLoadingLezioniProva) return const SizedBox.shrink();

    final now = DateTime.now();
    final limit = now.subtract(const Duration(days: 15));

    final entries = _utentiProva
        .map((u) {
          final courses = widget.allCourses
              .where(
                (c) =>
                    u.courses.contains(c.uid) &&
                    c.startDate.toDate().isAfter(limit) &&
                    c.startDate.toDate().isBefore(now),
              )
              .toList()
            ..sort(
              (a, b) => b.startDate.toDate().compareTo(a.startDate.toDate()),
            );
          return (u, courses);
        })
        .where((e) => e.$2.isNotEmpty)
        .toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return _buildLezioniProvaSection(
      title: 'Ultime lezioni di prova (${entries.length})',
      icon: Icons.history,
      bgColor: Colors.teal.shade50,
      borderColor: Colors.teal.shade300,
      headerColor: Colors.teal.shade700,
      avatarBgColor: Colors.teal.shade100,
      entries: entries,
    );
  }

  Widget _buildUtentiSenzaRegolamentoCard() {
    if (_isLoadingRegolamento) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Flexible(child: Text('Caricamento regolamento...')),
          ],
        ),
      );
    }

    // Filtra: utenti senza regolamento che hanno corsi nei prossimi 7 giorni
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 7));

    final entries = _utentiSenzaRegolamento
        .map((u) {
          final courses = widget.allCourses
              .where(
                (c) =>
                    u.courses.contains(c.uid) &&
                    c.startDate.toDate().isAfter(now) &&
                    c.startDate.toDate().isBefore(limit),
              )
              .toList()
            ..sort(
              (a, b) => a.startDate.toDate().compareTo(b.startDate.toDate()),
            );
          return (u, courses);
        })
        .where((e) => e.$2.isNotEmpty)
        .toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    final dateFmt = DateFormat('EEE dd/MM', 'it_IT');
    final timeFmt = DateFormat('HH:mm');

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: isDesktop(context) ? 4 : 8,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.shade300.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Regolamento non accettato (${entries.length})',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...entries.map((entry) {
            final (utente, courses) = entry;
            return InkWell(
              onTap: () async {
                await Navigator.push<FitropeUser>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailPage(user: utente),
                  ),
                );
                _loadUtentiSenzaRegolamento();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      radius: 20,
                      child: Text(
                        '${utente.name.isNotEmpty ? utente.name[0] : ''}${utente.lastName.isNotEmpty ? utente.lastName[0] : ''}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${utente.name} ${utente.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            utente.email,
                            style: const TextStyle(
                              fontSize: 12,
                              color: onSurfaceVariantColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...courses.map((c) {
                            final start = c.startDate.toDate();
                            final end = c.endDate.toDate();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.event,
                                    size: 14,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.name,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: onSurfaceColor,
                                          ),
                                        ),
                                        Text(
                                          '${dateFmt.format(start)}  ${timeFmt.format(start)} – ${timeFmt.format(end)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: onSurfaceVariantColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.orange.shade300,
                      size: 16,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCollapsibleRow({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: onSurfaceVariantColor,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: onSurfaceVariantColor,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCollapsibleRow(
            title: 'Scadenze',
            expanded: _scadenzeExpanded,
            onToggle: () =>
                setState(() => _scadenzeExpanded = !_scadenzeExpanded),
            children: [
              Expanded(child: _buildCertificatiInScadenzaCard()),
              const SizedBox(width: 16),
              Expanded(child: _buildAbbonamentiInScadenzaCard()),
            ],
          ),
          const SizedBox(height: 4),
          _buildCollapsibleRow(
            title: 'Lezioni di prova',
            expanded: _lezioniProvaExpanded,
            onToggle: () => setState(
              () => _lezioniProvaExpanded = !_lezioniProvaExpanded,
            ),
            children: [
              Expanded(child: _buildLezioniProvaProssimi7Giorni()),
              const SizedBox(width: 16),
              Expanded(child: _buildLezioniProvaUltimi15Giorni()),
            ],
          ),
          const SizedBox(height: 4),
          _buildCollapsibleRow(
            title: 'Regolamento',
            expanded: _regolamentoExpanded,
            onToggle: () =>
                setState(() => _regolamentoExpanded = !_regolamentoExpanded),
            children: [Expanded(child: _buildUtentiSenzaRegolamentoCard())],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCertificatiInScadenzaCard(),
        _buildAbbonamentiInScadenzaCard(),
        _buildLezioniProvaProssimi7Giorni(),
        _buildLezioniProvaUltimi15Giorni(),
      ],
    );
  }
}
