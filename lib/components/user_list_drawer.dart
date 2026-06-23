import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final DateFormat _dashboardUserListDateFormat = DateFormat('dd/MM/yyyy');

/// Drawer laterale con lista utenti ricercabile, usato da `Protected` come
/// endDrawer (aperto dalla dashboard admin). Estratto da AdminDashboardPage per
/// poter caricare quest'ultima in modo differito senza trascinare il drawer nel
/// chunk principale.
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
                    ? _dashboardUserListDateFormat
                        .format(u.fineIscrizione!.toDate())
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
