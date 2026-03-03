import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

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
            _SectionUtenti(users: users),
            const SizedBox(height: 24),
            _SectionCorsi(courses: coursesLast6Months),
            const SizedBox(height: 24),
            _SectionAbbonamenti(users: users),
          ],
        ),
      ),
    );
  }
}

class _SectionUtenti extends StatelessWidget {
  final List<FitropeUser> users;

  const _SectionUtenti({required this.users});

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

    return _DashboardCard(
      title: 'Utenti',
      icon: Icons.people,
      children: [
        _MetricRow('Totale', '${users.length}'),
        _MetricRow('Utenti attivi', '$active'),
        _MetricRow('Nuovi (ultimi 7 giorni)', '$new7'),
        _MetricRow('Nuovi (ultimi 30 giorni)', '$new30'),
        if (tipologiaEntries.isNotEmpty) ...[
          const Divider(height: 24),
          Text('Per tipologia iscrizione', style: _sectionLabelStyle(context)),
          const SizedBox(height: 12),
          _TipologieCorsiChart(
            entries: tipologiaEntries.map((e) => MapEntry(_labelTipologia(e.key), e.value)).toList(),
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

  const _SectionCorsi({required this.courses});

  @override
  Widget build(BuildContext context) {
    final full = courses.where((c) => c.subscribed >= c.capacity).length;
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

    return _DashboardCard(
      title: 'Corsi',
      icon: Icons.school,
      children: [
        _MetricRow('Corsi (ultimi 6 mesi)', '${courses.length}'),
        _MetricRow('Corsi al completo', '$full'),
        _MetricRow('Tasso di riempimento medio', '$avgFillPercent%'),
        if (tagEntries.isNotEmpty) ...[
          const Divider(height: 24),
          Text('Tipologie corsi', style: _sectionLabelStyle(context)),
          const SizedBox(height: 12),
          _TipologieCorsiChart(entries: tagEntries),
        ],
      ],
    );
  }
}

class _TipologieCorsiChart extends StatelessWidget {
  final List<MapEntry<String, int>> entries;

  const _TipologieCorsiChart({required this.entries});

  @override
  Widget build(BuildContext context) {
    final maxCount = entries.isEmpty ? 1 : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((e) {
        final pct = maxCount > 0 ? e.value / maxCount : 0.0;
        return Padding(
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
      }).toList(),
    );
  }
}

class _SectionAbbonamenti extends StatelessWidget {
  final List<FitropeUser> users;

  const _SectionAbbonamenti({required this.users});

  @override
  Widget build(BuildContext context) {
    final activeUsers = users.where((u) => u.isActive).toList();
    final now = DateTime.now();
    final in30Days = now.add(const Duration(days: 30));

    final expiringSoon = activeUsers.where((u) {
      if (u.fineIscrizione == null) return false;
      final end = u.fineIscrizione!.toDate();
      return end.isAfter(now) && end.isBefore(in30Days);
    }).length;

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
          (e) => _MetricRow(_labelTipologia(e.key), '${e.value}'),
        ),
        ...tipologiaEntries.expand((e) {
          final tagCounts = byTipologiaAndTag[e.key];
          if (tagCounts == null || tagCounts.isEmpty) return <Widget>[];
          final sorted = tagCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          return [
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              '${_labelTipologia(e.key)} – per tag',
              style: _sectionLabelStyle(context),
            ),
            const SizedBox(height: 8),
            _TipologieCorsiChart(entries: sorted),
          ];
        }),
        const Divider(height: 24),
        _MetricRow('In scadenza (prossimi 30 gg)', '$expiringSoon'),
        _MetricRow(
          'Pacchetti entrate: crediti medi residui',
          avgCredits.toStringAsFixed(1),
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

  const _MetricRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
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
  }
}
