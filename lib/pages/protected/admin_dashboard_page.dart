import 'package:fitrope_app/api/authentication/get_users.dart';
import 'package:fitrope_app/api/courses/get_courses.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/utils/refresh_manager.dart';
import 'package:fitrope_app/pages/protected/user_detail_page.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/subscription_labels.dart';
import 'package:fitrope_app/utils/subscription_expiry.dart';
import 'package:fitrope_app/utils/download_file.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/subscription_duration.dart';
import 'package:fitrope_app/utils/users_csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final DateFormat _dashboardUserListDateFormat = DateFormat('dd/MM/yyyy');

class AdminDashboardPage extends StatefulWidget {
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const AdminDashboardPage({super.key, required this.onOpenUserList});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  List<FitropeUser>? _users;
  List<Course>? _courses;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    RefreshManager().addListener(_loadData);
  }

  @override
  void dispose() {
    RefreshManager().removeListener(_loadData);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await getUsers();
      final courses = await getAllCourses();
      if (mounted) {
        setState(() {
          _users = users;
          _courses = courses;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop(context)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(pagePadding * 2),
          child: Text(
            'Dashboard disponibile solo su desktop',
            style: TextStyle(
              fontSize: 18,
              color: onSurfaceVariantColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Errore: $_error',
                  style: const TextStyle(color: errorColor)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadData,
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
    }

    final users = _users!;
    final courses = _courses!;
    final now = DateTime.now();
    final sixMonthsAgo = now.subtract(const Duration(days: 180));
    final coursesLast6Months = courses
        .where((c) => c.startDate.toDate().isAfter(sixMonthsAgo))
        .toList();
    // Le sezioni analitiche guardano solo i clienti: profili attivi con almeno
    // un abbonamento non scaduto. L'ultima sezione elenca il complemento.
    final clients = users
        .where((u) => u.isActive && hasLiveSubscription(u, now: now))
        .toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Dashboard analisi',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: onSurfaceColor,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            _SectionUtenti(
              clients: clients,
              now: now,
              onOpenUserList: widget.onOpenUserList,
            ),
            const SizedBox(height: 24),
            _SectionCorsi(
              courses: coursesLast6Months,
              clients: clients,
              onOpenUserList: widget.onOpenUserList,
            ),
            const SizedBox(height: 24),
            _SectionAbbonamenti(
              clients: clients,
              now: now,
              onOpenUserList: widget.onOpenUserList,
            ),
            const SizedBox(height: 24),
            _SectionAbbonamentiSenzaData(
              users: users,
              now: now,
              onOpenUserList: widget.onOpenUserList,
            ),
          ],
        ),
      ),
    );
  }
}

/// Drawer laterale con lista utenti ricercabile. Usato da [Protected] per coprire l'intera pagina con la scrim.
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
            title: Text(widget.title),
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
    final date = _dashboardUserListDateFormat.format(end);
    if (now.isAfter(end)) {
      return Text('Scaduto il $date',
          style: _style.copyWith(color: errorColor));
    }
    return Text('Scade il $date', style: _style);
  }
}

class _SectionUtenti extends StatelessWidget {
  final List<FitropeUser> clients;
  final DateTime now;
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const _SectionUtenti({
    required this.clients,
    required this.now,
    required this.onOpenUserList,
  });

  @override
  Widget build(BuildContext context) {
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final new7List =
        clients.where((u) => u.createdAt.isAfter(sevenDaysAgo)).toList();
    final new30List =
        clients.where((u) => u.createdAt.isAfter(thirtyDaysAgo)).toList();
    final new7 = new7List.length;
    final new30 = new30List.length;

    final durationEntries = usersBySubscriptionDuration(clients, now: now);
    final familyEntries = usersBySubscriptionFamily(clients, now: now);

    return _DashboardCard(
      title: 'Utenti',
      icon: Icons.people,
      children: [
        _MetricRow('Clienti con abbonamento attivo', '${clients.length}',
            onTap: () =>
                onOpenUserList('Clienti con abbonamento attivo', clients)),
        _MetricRow('Nuovi (ultimi 7 giorni)', '$new7',
            onTap: () => onOpenUserList('Nuovi (ultimi 7 giorni)', new7List)),
        _MetricRow('Nuovi (ultimi 30 giorni)', '$new30',
            onTap: () => onOpenUserList('Nuovi (ultimi 30 giorni)', new30List)),
        const Divider(height: 24),
        Text('Per durata abbonamento', style: _sectionLabelStyle(context)),
        const SizedBox(height: 12),
        _TipologieCorsiChart(
          entries: durationEntries
              .map((e) => MapEntry(e.key.label, e.value.length))
              .toList(),
          userListsPerEntry: durationEntries.map((e) => e.value).toList(),
          onEntryTap: (i) => onOpenUserList(
              durationEntries[i].key.label, durationEntries[i].value),
        ),
        const Text(
          'Un socio con abbonamenti di durate diverse compare in ciascuna voce.',
          style: TextStyle(color: onSurfaceVariantColor, fontSize: 13),
        ),
        const Divider(height: 24),
        Text('Abbonamenti per tipologia', style: _sectionLabelStyle(context)),
        const SizedBox(height: 12),
        _TipologieCorsiChart(
          entries: familyEntries
              .map((e) =>
                  MapEntry(getSubscriptionFamilyLabel(e.key), e.value.length))
              .toList(),
          userListsPerEntry: familyEntries.map((e) => e.value).toList(),
          onEntryTap: (i) => onOpenUserList(
              getSubscriptionFamilyLabel(familyEntries[i].key),
              familyEntries[i].value),
        ),
      ],
    );
  }
}

class _SectionCorsi extends StatelessWidget {
  final List<Course> courses;
  final List<FitropeUser> clients;
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const _SectionCorsi({
    required this.courses,
    required this.clients,
    required this.onOpenUserList,
  });

  @override
  Widget build(BuildContext context) {
    final fullCourses =
        courses.where((c) => c.subscribed >= c.capacity).toList();
    final full = fullCourses.length;
    double avgFill = 0;
    if (courses.isNotEmpty) {
      var sum = 0.0;
      for (final c in courses) {
        if (c.capacity > 0) sum += c.subscribed / c.capacity;
      }
      avgFill = sum / courses.length;
    }
    final avgFillPercent = (avgFill * 100).toStringAsFixed(1);

    final byTag = <String, int>{};
    for (final c in courses) {
      final tag = c.displayTag ?? c.resolvedTypeTag;
      byTag[tag] = (byTag[tag] ?? 0) + 1;
    }
    final tagEntries = byTag.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final courseIdsLast6Months = courses.map((c) => c.uid).toSet();
    final usersWithCourseLast6Months = clients
        .where((u) => u.courses.any((id) => courseIdsLast6Months.contains(id)))
        .toList();
    final usersInFullCourse = clients
        .where(
            (u) => u.courses.any((id) => fullCourses.any((c) => c.uid == id)))
        .toList();

    final userListsByTag = tagEntries.map((e) {
      final tag = e.key;
      return clients
          .where((u) => u.courses.any((courseId) {
                final c = courses.where((c) => c.uid == courseId).firstOrNull;
                if (c == null) return false;
                final courseTag = c.displayTag ?? c.resolvedTypeTag;
                return courseTag == tag;
              }))
          .toList();
    }).toList();

    return _DashboardCard(
      title: 'Corsi',
      icon: Icons.school,
      children: [
        _MetricRow('Corsi (ultimi 6 mesi)', '${courses.length}',
            onTap: () => onOpenUserList(
                'Corsi (ultimi 6 mesi) – utenti iscritti',
                usersWithCourseLast6Months)),
        _MetricRow('Corsi al completo', '$full',
            onTap: () => onOpenUserList(
                'Corsi al completo – utenti iscritti', usersInFullCourse)),
        _MetricRow('Tasso di riempimento medio', '$avgFillPercent%'),
        if (tagEntries.isNotEmpty) ...[
          const Divider(height: 24),
          Text('Tipologie corsi', style: _sectionLabelStyle(context)),
          const SizedBox(height: 12),
          _TipologieCorsiChart(
            entries: tagEntries,
            userListsPerEntry: userListsByTag,
            onEntryTap: (i) => onOpenUserList(
                'Tipologia corso: ${tagEntries[i].key}', userListsByTag[i]),
          ),
        ],
      ],
    );
  }
}

class _TipologieCorsiChart extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final List<List<FitropeUser>>? userListsPerEntry;
  final void Function(int index)? onEntryTap;

  const _TipologieCorsiChart({
    required this.entries,
    this.userListsPerEntry,
    this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxCount = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final canTap = onEntryTap != null &&
        userListsPerEntry != null &&
        userListsPerEntry!.length == entries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final pct = maxCount > 0 ? e.value / maxCount : 0.0;
        final row = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key,
                      style:
                          const TextStyle(color: onSurfaceColor, fontSize: 14)),
                  Text('${e.value}',
                      style: const TextStyle(
                          color: onSurfaceColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: outlineVariantColor,
                  valueColor: const AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
            ],
          ),
        );
        if (canTap && e.value > 0) {
          return InkWell(
            onTap: () => onEntryTap!(i),
            borderRadius: BorderRadius.circular(4),
            child: row,
          );
        }
        return row;
      }).toList(),
    );
  }
}

class _SectionAbbonamenti extends StatelessWidget {
  final List<FitropeUser> clients;
  final DateTime now;
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const _SectionAbbonamenti({
    required this.clients,
    required this.now,
    required this.onOpenUserList,
  });

  @override
  Widget build(BuildContext context) {
    final expiringSoonList = clients
        .where((u) => hasSubscriptionExpiringInNext30Days(u, now: now))
        .toList();
    final expiringSoon =
        countSubscriptionsExpiringInNext30Days(clients, now: now);

    final (entryUsers, avgEntries) = averageRemainingEntries(clients, now: now);

    return _DashboardCard(
      title: 'Abbonamenti',
      icon: Icons.card_membership,
      children: [
        _MetricRow('Abbonamenti in scadenza (prossimi 30 gg)', '$expiringSoon',
            onTap: () => onOpenUserList(
                'Abbonamenti in scadenza (prossimi 30 gg)', expiringSoonList)),
        _MetricRow(
          'Ingressi medi residui (piani a ingressi)',
          avgEntries.toStringAsFixed(1),
          onTap: () => onOpenUserList('Piani a ingressi', entryUsers),
        ),
      ],
    );
  }
}

/// Sezione che elenca i profili senza abbonamenti non scaduti: complemento
/// dei clienti delle altre sezioni ([hasNoActiveSubscription]), Admin e
/// Trainer esclusi. Chi ha solo abbonamenti scaduti compare qui.
class _SectionAbbonamentiSenzaData extends StatelessWidget {
  final List<FitropeUser> users;
  final DateTime now;
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const _SectionAbbonamentiSenzaData({
    required this.users,
    required this.now,
    required this.onOpenUserList,
  });

  @override
  Widget build(BuildContext context) {
    final senzaData = users
        .where((u) =>
            hasNoActiveSubscription(u, now: now) &&
            u.role != 'Admin' &&
            u.role != 'Trainer')
        .toList()
      ..sort((a, b) => ('${a.name} ${a.lastName}')
          .toLowerCase()
          .compareTo(('${b.name} ${b.lastName}').toLowerCase()));

    return _DashboardCard(
      title: 'Clienti con nessun abbonamento attivo',
      icon: Icons.event_busy,
      children: [
        _MetricRow(
          'Nessun abbonamento attivo',
          '${senzaData.length}',
          onTap: senzaData.isEmpty
              ? null
              : () => onOpenUserList(
                  'Clienti con nessun abbonamento attivo', senzaData),
        ),
        const SizedBox(height: 8),
        if (senzaData.isEmpty)
          const Text(
            'Tutti i profili hanno almeno un abbonamento attivo.',
            style: TextStyle(color: onSurfaceVariantColor, fontSize: 13),
          )
        else
          const Text(
            'Tocca per aprire l\'elenco dei profili senza abbonamenti attivi.',
            style: TextStyle(color: onSurfaceVariantColor, fontSize: 13),
          ),
      ],
    );
  }
}

TextStyle _sectionLabelStyle(BuildContext context) {
  return const TextStyle(
    fontWeight: FontWeight.w600,
    color: onSurfaceVariantColor,
    fontSize: 14,
  );
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _DashboardCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: outlineVariantColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: onSurfaceColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _MetricRow(this.label, this.value, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: onSurfaceColor)),
          Text(
            value,
            style: const TextStyle(
              color: onSurfaceColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: row,
      );
    }
    return row;
  }
}
