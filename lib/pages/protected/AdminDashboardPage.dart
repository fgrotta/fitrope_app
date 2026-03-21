import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/utils/abbonamento_helper.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(pagePadding * 2),
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
              Text('Errore: $_error', style: TextStyle(color: errorColor)),
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
    final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
    final coursesLast6Months = courses
        .where((c) => c.startDate.toDate().isAfter(sixMonthsAgo))
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
              _SectionUtenti(users: users, onOpenUserList: widget.onOpenUserList),
              const SizedBox(height: 24),
              _SectionCorsi(
                courses: coursesLast6Months,
                users: users,
                onOpenUserList: widget.onOpenUserList,
              ),
              const SizedBox(height: 24),
              _SectionAbbonamenti(users: users, onOpenUserList: widget.onOpenUserList),
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

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredUsers;
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
            style: TextStyle(
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
                final hasScadenza = u.fineIscrizione != null;
                final scadenzaText = hasScadenza
                    ? _dashboardUserListDateFormat.format(u.fineIscrizione!.toDate())
                    : '—';
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
                              style: TextStyle(
                                fontSize: 13,
                                color: onSurfaceVariantColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              hasPhone ? phone : '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: onSurfaceVariantColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Scadenza abb.: $scadenzaText',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12,
                                color: onSurfaceVariantColor,
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _SectionUtenti extends StatelessWidget {
  final List<FitropeUser> users;
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const _SectionUtenti({required this.users, required this.onOpenUserList});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));

    final active = users.where((u) => u.isActive).length;
    final new7 = users.where((u) => u.createdAt.isAfter(sevenDaysAgo)).length;
    final new30 = users.where((u) => u.createdAt.isAfter(thirtyDaysAgo)).length;

    final byTipologia = <TipologiaIscrizione, int>{};
    for (final u in users) {
      if (u.tipologiaIscrizione != null) {
        byTipologia[u.tipologiaIscrizione!] =
            (byTipologia[u.tipologiaIscrizione!] ?? 0) + 1;
      }
    }
    final tipologiaEntries = byTipologia.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final activeList = users.where((u) => u.isActive).toList();
    final new7List = users.where((u) => u.createdAt.isAfter(sevenDaysAgo)).toList();
    final new30List = users.where((u) => u.createdAt.isAfter(thirtyDaysAgo)).toList();

    return _DashboardCard(
      title: 'Utenti',
      icon: Icons.people,
      children: [
        _MetricRow('Totale', '${users.length}', onTap: () => onOpenUserList('Totale', users)),
        _MetricRow('Utenti attivi', '$active', onTap: () => onOpenUserList('Utenti attivi', activeList)),
        _MetricRow('Nuovi (ultimi 7 giorni)', '$new7', onTap: () => onOpenUserList('Nuovi (ultimi 7 giorni)', new7List)),
        _MetricRow('Nuovi (ultimi 30 giorni)', '$new30', onTap: () => onOpenUserList('Nuovi (ultimi 30 giorni)', new30List)),
        if (tipologiaEntries.isNotEmpty) ...[
          const Divider(height: 24),
          Text('Per tipologia iscrizione', style: _sectionLabelStyle(context)),
          const SizedBox(height: 12),
          _TipologieCorsiChart(
            entries: tipologiaEntries.map((e) => MapEntry(_labelTipologia(e.key), e.value)).toList(),
            userListsPerEntry: tipologiaEntries.map((e) => users.where((u) => u.tipologiaIscrizione == e.key).toList()).toList(),
            onEntryTap: (i) => onOpenUserList(_labelTipologia(tipologiaEntries[i].key), users.where((u) => u.tipologiaIscrizione == tipologiaEntries[i].key).toList()),
          ),
        ],
      ],
    );
  }

  String _labelTipologia(TipologiaIscrizione t) {
    final s = t.toString().split('.').last;
    return s.replaceAll('_', ' ');
  }
}

class _SectionCorsi extends StatelessWidget {
  final List<Course> courses;
  final List<FitropeUser> users;
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const _SectionCorsi({
    required this.courses,
    required this.users,
    required this.onOpenUserList,
  });

  @override
  Widget build(BuildContext context) {
    final fullCourses = courses.where((c) => c.subscribed >= c.capacity).toList();
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
      final tag = c.tags.isNotEmpty ? c.tags.first : 'Nessun tag';
      byTag[tag] = (byTag[tag] ?? 0) + 1;
    }
    final tagEntries = byTag.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final courseIdsLast6Months = courses.map((c) => c.uid).toSet();
    final usersWithCourseLast6Months = users.where((u) => u.courses.any((id) => courseIdsLast6Months.contains(id))).toList();
    final usersInFullCourse = users.where((u) => u.courses.any((id) => fullCourses.any((c) => c.uid == id))).toList();

    final userListsByTag = tagEntries.map((e) {
      final tag = e.key;
      return users.where((u) => u.courses.any((courseId) {
        final c = courses.where((c) => c.uid == courseId).firstOrNull;
        if (c == null) return false;
        final courseTag = c.tags.isNotEmpty ? c.tags.first : 'Nessun tag';
        return courseTag == tag;
      })).toList();
    }).toList();

    return _DashboardCard(
      title: 'Corsi',
      icon: Icons.school,
      children: [
        _MetricRow('Corsi (ultimi 6 mesi)', '${courses.length}', onTap: () => onOpenUserList('Corsi (ultimi 6 mesi) – utenti iscritti', usersWithCourseLast6Months)),
        _MetricRow('Corsi al completo', '$full', onTap: () => onOpenUserList('Corsi al completo – utenti iscritti', usersInFullCourse)),
        _MetricRow('Tasso di riempimento medio', '$avgFillPercent%'),
        if (tagEntries.isNotEmpty) ...[
          const Divider(height: 24),
          Text('Tipologie corsi', style: _sectionLabelStyle(context)),
          const SizedBox(height: 12),
          _TipologieCorsiChart(
            entries: tagEntries,
            userListsPerEntry: userListsByTag,
            onEntryTap: (i) => onOpenUserList('Tipologia corso: ${tagEntries[i].key}', userListsByTag[i]),
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
    final maxCount = entries.isEmpty ? 1 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final canTap = onEntryTap != null && userListsPerEntry != null && userListsPerEntry!.length == entries.length;

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
                  Text(e.key, style: TextStyle(color: onSurfaceColor, fontSize: 14)),
                  Text('${e.value}', style: TextStyle(color: onSurfaceColor, fontWeight: FontWeight.w600, fontSize: 14)),
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
        if (canTap) {
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
  final List<FitropeUser> users;
  final void Function(String title, List<FitropeUser> users) onOpenUserList;

  const _SectionAbbonamenti({required this.users, required this.onOpenUserList});

  @override
  Widget build(BuildContext context) {
    final activeUsers = users.where((u) => u.isActive).toList();

    final expiringSoonList = activeUsers
        .where((u) =>
            AbbonamentoHelper.isFineIscrizioneNeiProssimi30Giorni(u.fineIscrizione))
        .toList();
    final expiringSoon = expiringSoonList.length;

    final pacchettoUsers = activeUsers.where((u) {
      return u.tipologiaIscrizione == TipologiaIscrizione.PACCHETTO_ENTRATE ||
          u.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_PROVA;
    }).toList();
    double avgCredits = 0;
    if (pacchettoUsers.isNotEmpty) {
      final sum = pacchettoUsers.fold<int>(
        0,
        (s, u) => s + (u.entrateDisponibili ?? 0),
      );
      avgCredits = sum / pacchettoUsers.length;
    }

    final byTipologia = <TipologiaIscrizione, int>{};
    for (final u in activeUsers) {
      if (u.tipologiaIscrizione != null) {
        byTipologia[u.tipologiaIscrizione!] =
            (byTipologia[u.tipologiaIscrizione!] ?? 0) + 1;
      }
    }

    // Per ogni tipologia, conteggio utenti per tag (tipologiaCorsoTags)
    final byTipologiaAndTag = <TipologiaIscrizione, Map<String, int>>{};
    for (final u in activeUsers) {
      if (u.tipologiaIscrizione == null) continue;
      final tip = u.tipologiaIscrizione!;
      byTipologiaAndTag.putIfAbsent(tip, () => {});
      final tags = u.tipologiaCorsoTags.isEmpty ? ['Nessun tag'] : u.tipologiaCorsoTags;
      for (final tag in tags) {
        byTipologiaAndTag[tip]![tag] = (byTipologiaAndTag[tip]![tag] ?? 0) + 1;
      }
    }

    final tipologiaEntries = byTipologia.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _DashboardCard(
      title: 'Abbonamenti',
      icon: Icons.card_membership,
      children: [
        Text('Distribuzione per tipologia', style: _sectionLabelStyle(context)),
        const SizedBox(height: 8),
        ...tipologiaEntries.map(
          (e) => _MetricRow(
            _labelTipologia(e.key),
            '${e.value}',
            onTap: () => onOpenUserList(_labelTipologia(e.key), activeUsers.where((u) => u.tipologiaIscrizione == e.key).toList()),
          ),
        ),
        ...tipologiaEntries.expand((e) {
          final tagCounts = byTipologiaAndTag[e.key];
          if (tagCounts == null || tagCounts.isEmpty) return <Widget>[];
          final sorted = tagCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final usersForTipologia = activeUsers.where((u) => u.tipologiaIscrizione == e.key).toList();
          final userListsPerTag = sorted.map((tagEntry) => usersForTipologia.where((u) {
            final tags = u.tipologiaCorsoTags.isEmpty ? ['Nessun tag'] : u.tipologiaCorsoTags;
            return tags.contains(tagEntry.key);
          }).toList()).toList();
          return [
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              '${_labelTipologia(e.key)} – per tag',
              style: _sectionLabelStyle(context),
            ),
            const SizedBox(height: 8),
            _TipologieCorsiChart(
              entries: sorted,
              userListsPerEntry: userListsPerTag,
              onEntryTap: (i) => onOpenUserList('${_labelTipologia(e.key)} – ${sorted[i].key}', userListsPerTag[i]),
            ),
          ];
        }),
        const Divider(height: 24),
        _MetricRow('In scadenza (prossimi 30 gg)', '$expiringSoon', onTap: () => onOpenUserList('In scadenza (prossimi 30 gg)', expiringSoonList)),
        _MetricRow(
          'Pacchetti entrate: crediti medi residui',
          avgCredits.toStringAsFixed(1),
          onTap: () => onOpenUserList('Pacchetti entrate / Abbonamento prova', pacchettoUsers),
        ),
      ],
    );
  }

  String _labelTipologia(TipologiaIscrizione t) {
    final s = t.toString().split('.').last;
    return s.replaceAll('_', ' ');
  }
}

TextStyle _sectionLabelStyle(BuildContext context) {
  return TextStyle(
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
        side: BorderSide(color: outlineVariantColor),
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
          Text(label, style: TextStyle(color: onSurfaceColor)),
          Text(
            value,
            style: TextStyle(
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
