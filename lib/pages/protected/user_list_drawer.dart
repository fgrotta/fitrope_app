import 'package:fitrope_app/pages/protected/user_detail_page.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/subscription_expiry.dart';
import 'package:fitrope_app/utils/download_file.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/users_csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final DateFormat _userListDateFormat = DateFormat('dd/MM/yyyy');

/// Drawer laterale con lista utenti ricercabile. Usato da [Protected] per coprire l'intera pagina con la scrim.
///
/// File a sé perché `Protected` lo importa con `deferred as`: lo apre solo la
/// dashboard admin, un socio non ne scarica il codice.
class UserListDrawer extends StatefulWidget {
  final String title;
  final List<FitropeUser> users;
  final VoidCallback onClose;

  const UserListDrawer({
    super.key,
    required this.title,
    required this.users,
    required this.onClose,
  });

  @override
  State<UserListDrawer> createState() => _UserListDrawerState();
}

class _UserListDrawerState extends State<UserListDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FitropeUser> get _filteredUsers {
    if (_query.isEmpty) return widget.users;
    return widget.users.where((u) {
      final name = '${u.name} ${u.lastName}'.toLowerCase();
      final email = u.email.toLowerCase();
      final phone = (u.numeroTelefono ?? '').toLowerCase();
      return name.contains(_query) ||
          email.contains(_query) ||
          phone.contains(_query);
    }).toList();
  }

  /// Esporta in CSV **quello che si vede**: `_filteredUsers`, non
  /// `widget.users`, perché il drawer ha una ricerca.
  ///
  /// Volutamente sincrona: i dati sono già in memoria (li carica
  /// `_AdminDashboardPageState._loadData`). Non introdurre `await` tra il click
  /// e [downloadTextFile] — Safari e Firefox smettono di considerare il download
  /// user-initiated e lo bloccano **in silenzio**.
  void _exportCsv() {
    final users = _filteredUsers;
    if (users.isEmpty) {
      SnackBarUtils.showWarningSnackBar(context, 'Nessun utente da esportare');
      return;
    }
    try {
      downloadTextFile(
        content: buildUsersCsv(users),
        fileName: usersCsvFileName(widget.title, DateTime.now()),
      );
      SnackBarUtils.showSuccessSnackBar(
          context, 'Esportati ${users.length} utenti');
    } catch (error) {
      SnackBarUtils.showErrorSnackBar(context, 'Export non riuscito: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers;
    final now = DateTime.now();
    return Drawer(
      child: Column(
        children: [
          AppBar(
            // I titoli arrivano dalle voci della dashboard e superano spesso
            // la larghezza del drawer: due righe invece di troncarli.
            title: Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                Scaffold.of(context).closeEndDrawer();
                widget.onClose();
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Esporta in CSV',
                onPressed: _exportCsv,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cerca per nome, email o telefono...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
              ),
              autofocus: false,
            ),
          ),
          Text(
            '${filtered.length} utenti',
            style: const TextStyle(
              fontSize: 12,
              color: onSurfaceVariantColor,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final u = filtered[index];
                final phone = u.numeroTelefono?.trim();
                final hasPhone = phone != null && phone.isNotEmpty;
                return ListTile(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${u.name} ${u.lastName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: Text(
                              u.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: onSurfaceVariantColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasPhone ? phone : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: onSurfaceVariantColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _UserSubscriptionLines(user: u, now: now),
                    ],
                  ),
                  dense: true,
                  onTap: () {
                    Scaffold.of(context).closeEndDrawer();
                    widget.onClose();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => UserDetailPage(user: u),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Una riga per abbonamento: tipologia a sinistra, scadenza a destra (o sotto,
/// se non c'è spazio). Prima
/// era un'unica riga "Scadenza abb.: …" a metà larghezza e `maxLines: 1`, che
/// veniva troncata subito dopo l'etichetta e non mostrava né piano né data.
class _UserSubscriptionLines extends StatelessWidget {
  final FitropeUser user;
  final DateTime now;

  const _UserSubscriptionLines({required this.user, required this.now});

  static const _style = TextStyle(fontSize: 12, color: onSurfaceVariantColor);

  @override
  Widget build(BuildContext context) {
    final expiries = subscriptionExpiries(user, now: now)
        .where((e) => e.endDate != null)
        .toList();
    if (expiries.isEmpty) {
      return const Text('Nessun abbonamento attivo', style: _style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final expiry in expiries)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            // Wrap e non Row: se piano e data non stanno su una riga la data
            // va a capo, invece di troncare il piano o andare in overflow.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 10,
              children: [
                Text(expiry.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _style.copyWith(color: onSurfaceColor)),
                _expiryText(expiry.endDate!.toDate()),
              ],
            ),
          ),
      ],
    );
  }

  Widget _expiryText(DateTime end) {
    final date = _userListDateFormat.format(end);
    if (now.isAfter(end)) {
      return Text('Scaduto il $date',
          style: _style.copyWith(color: errorColor));
    }
    return Text('Scade il $date', style: _style);
  }
}
