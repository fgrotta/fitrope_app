import 'package:fitrope_app/pages/protected/guide/guide_catalog.dart';
import 'package:fitrope_app/pages/protected/guide/guide_page.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

/// Indice della Guida Admin: guide raggruppate per categoria, con ricerca su
/// titolo e riassunto.
class GuideIndexPage extends StatefulWidget {
  final List<GuideEntry> catalog;

  const GuideIndexPage({super.key, this.catalog = guideCatalog});

  @override
  State<GuideIndexPage> createState() => _GuideIndexPageState();
}

class _GuideIndexPageState extends State<GuideIndexPage> {
  String _query = '';

  bool _matches(GuideEntry entry) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return entry.title.toLowerCase().contains(q) ||
        entry.summary.toLowerCase().contains(q);
  }

  void _open(GuideEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GuidePage(entry: entry, catalog: widget.catalog),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.catalog.where(_matches).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: const Text('Guida'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: guideMaxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(pagePadding),
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Cerca nella guida',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'Nessuna guida trovata',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: onSurfaceVariantColor),
                  ),
                ),
              for (final category in GuideCategory.values)
                if (visible.any((e) => e.category == category)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 8),
                    child: Text(
                      category.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: onPrimaryColor,
                      ),
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    color: surfaceColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: outlineColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final entry
                            in visible.where((e) => e.category == category))
                          ListTile(
                            leading: Icon(entry.icon, color: primaryColor),
                            title: Text(entry.title),
                            subtitle: Text(entry.summary),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(entry),
                          ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
