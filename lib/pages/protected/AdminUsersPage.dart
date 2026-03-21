import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/authentication/toggleUserStatus.dart';
import 'package:fitrope_app/authentication/resetPassword.dart';
import 'package:fitrope_app/utils/abbonamento_helper.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/course_tags.dart';
import 'package:fitrope_app/utils/getTipologiaIscrizioneLabel.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/layout/breakpoints.dart';
import 'package:fitrope_app/pages/protected/CreateUserPage.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show FixedColumnWidth;
import 'package:flutter_redux/flutter_redux.dart';
import 'package:intl/intl.dart';

enum AbbonamentoScadenzaListFilter {
  tutti,
  inScadenzaProssimi30Giorni,
  senzaScadenza,
}

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<FitropeUser> users = [];
  List<FitropeUser> filteredUsers = [];
  List<FitropeUser> displayedUsers = []; // Utenti visualizzati nella lista
  TextEditingController searchController = TextEditingController();
  ScrollController scrollController = ScrollController();
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  late FitropeUser user;
  static const int _itemsPerPage = 20; // Numero di utenti da caricare per volta
  static const double _userTableNarrowColumnWidth = 100;
  static const EdgeInsets _userTableNarrowCellPadding =
      EdgeInsets.symmetric(horizontal: 6, vertical: 8);
  static final DateFormat _userTableDateFormat = DateFormat('dd/MM/yyyy');

  Widget _userTableEllipsisText(String text, {TextStyle? style}) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  String _desktopTableTelefonoCell(FitropeUser u) {
    final t = u.numeroTelefono?.trim();
    return (t == null || t.isEmpty) ? '—' : t;
  }

  String _desktopTableScadenzaAbbonamentoCell(FitropeUser u) {
    final ts = u.fineIscrizione;
    return ts == null ? 'Non impostata' : _userTableDateFormat.format(ts.toDate());
  }

  /// Filtro tag: null = tutti i tag
  String? selectedTagFilter;
  /// Filtro tipologia abbonamento: null = tutte le tipologie
  TipologiaIscrizione? selectedTipologiaFilter;
  /// Filtro stato: null = tutti, true = solo attivi, false = solo disattivati
  bool? activeFilter;
  /// Solo Admin: filtro su fine iscrizione (allineato al KPI dashboard per i 30 gg)
  AbbonamentoScadenzaListFilter _abbonamentoScadenzaFilter =
      AbbonamentoScadenzaListFilter.tutti;
  /// Su mobile: filtri nascosti o mostrati (dropdown espanso/collassato)
  bool _filtersExpanded = false;

  @override
  void initState() {
    super.initState();
    user = store.state.user!;
    loadUsers();
    scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (scrollController.position.pixels >= 
        scrollController.position.maxScrollExtent - 200) {
      // Carica più elementi quando si è a 200px dalla fine
      _loadMoreUsers();
    }
  }

  Future<void> loadUsers() async {
    setState(() {
      isLoading = true;
      displayedUsers = [];
      hasMore = true;
    });

    try {
      final usersList = await getUsers();

      setState(() {
        users = usersList;
        isLoading = false;
      });
      
      _applyFilters();
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        isLoading = false;
      }); 
    }
  }

  void _loadMoreUsers() {
    if (isLoadingMore || !hasMore) return;

    setState(() {
      isLoadingMore = true;
    });

    // Simula un piccolo delay per evitare troppe chiamate
    Future.delayed(Duration(milliseconds: 100), () {
      if (!mounted) return;
      
      final currentLength = displayedUsers.length;
      final nextLength = currentLength + _itemsPerPage;
      
      setState(() {
        displayedUsers = filteredUsers.take(nextLength).toList();
        hasMore = nextLength < filteredUsers.length;
        isLoadingMore = false;
      });
    });
  }

  void _applyFilters() {
    setState(() {
      var result = users;

      // Filtro testo (nome/email)
      final query = searchController.text.trim();
      if (query.isNotEmpty) {
        final searchQuery = query.toLowerCase();
        result = result.where((u) {
          final fullName = '${u.name} ${u.lastName}'.toLowerCase();
          final email = u.email.toLowerCase();
          return fullName.contains(searchQuery) || email.contains(searchQuery);
        }).toList();
      }

      // Filtro tag
      if (selectedTagFilter != null) {
        result = result.where((u) => u.tipologiaCorsoTags.contains(selectedTagFilter!)).toList();
      }

      // Filtro tipologia abbonamento
      if (selectedTipologiaFilter != null) {
        result = result.where((u) => u.tipologiaIscrizione == selectedTipologiaFilter).toList();
      }

      // Filtro stato (attivi / disattivati)
      if (activeFilter != null) {
        result = result.where((u) => u.isActive == activeFilter).toList();
      }

      // Filtro scadenza abbonamento (solo Admin)
      if (user.role == 'Admin') {
        switch (_abbonamentoScadenzaFilter) {
          case AbbonamentoScadenzaListFilter.tutti:
            break;
          case AbbonamentoScadenzaListFilter.inScadenzaProssimi30Giorni:
            result = result
                .where((u) =>
                    AbbonamentoHelper.isFineIscrizioneNeiProssimi30Giorni(
                      u.fineIscrizione,
                    ))
                .toList();
            break;
          case AbbonamentoScadenzaListFilter.senzaScadenza:
            result = result.where((u) => u.fineIscrizione == null).toList();
            break;
        }
      }

      filteredUsers = result;
      displayedUsers = [];
      hasMore = true;
    });
    _loadMoreUsers();
  }

  void filterUsers(String query) {
    _applyFilters();
  }

  bool _canEditListedUser(FitropeUser target) {
    if (user.uid == target.uid) return true;
    if (user.role == 'Admin') return true;
    if (user.role == 'Trainer' && target.role == 'User') return true;
    return false;
  }

  bool _canSendResetPasswordFromList() => user.role == 'Admin';

  void showUserDetails(FitropeUser targetUser, {bool openInEditMode = false}) async {
    final updatedUser = await Navigator.push<FitropeUser>(
      context,
      MaterialPageRoute(
        builder: (context) => UserDetailPage(
          user: targetUser,
          openInEditMode: openInEditMode,
        ),
      ),
    );
    
    // Se l'utente è stato aggiornato, aggiorna la lista
    if (updatedUser != null) {
      setState(() {
        final index = users.indexWhere((u) => u.uid == updatedUser.uid);
        if (index != -1) {
          users[index] = updatedUser;
          _applyFilters();
        }
      });
    }
  }

  void _showResetPasswordDialog(FitropeUser targetUser) {
    if (targetUser.email.trim().isEmpty) {
      SnackBarUtils.showErrorSnackBar(
        context,
        'Nessun indirizzo email per questo utente',
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          title: const Text('Invia Email Reset Password'),
          content: Text(
            'Sei sicuro di voler inviare un\'email di reset password a ${targetUser.email}?\n\n'
            'L\'utente riceverà un\'email con le istruzioni per reimpostare la propria password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla', style: TextStyle(color: onPrimaryColor)),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await resetPassword(targetUser.email);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  SnackBarUtils.showSuccessSnackBar(
                    context,
                    'Email di reset password inviata con successo a ${targetUser.email}',
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  SnackBarUtils.showErrorSnackBar(
                    context,
                    'Errore durante l\'invio dell\'email di reset password',
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: primaryColor),
              child: const Text(
                'Invia Email',
                style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void showToggleUserStatusDialog(FitropeUser user) {
    final isCurrentlyActive = user.isActive;
    final action = isCurrentlyActive ? 'disattivare' : 'attivare';
    final actionPast = isCurrentlyActive ? 'disattivato' : 'attivato';
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          title: Text(isCurrentlyActive ? 'Disattiva Utente' : 'Attiva Utente'),
          content: Text('Sei sicuro di voler $action l\'utente ${user.name} ${user.lastName}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla', style: TextStyle(color: onPrimaryColor),),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await toggleUserStatus(user.uid, !isCurrentlyActive);
                  Navigator.pop(context);
                  loadUsers(); // Ricarica la lista
                  SnackBarUtils.showSuccessSnackBar(
                    context,
                    'Utente $actionPast con successo',
                  );
                } catch (e) {
                  Navigator.pop(context);
                  SnackBarUtils.showErrorSnackBar(
                    context,
                    'Errore durante l\'operazione',
                  );
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: isCurrentlyActive ? Colors.orange : Colors.green
              ),
              child: Text(isCurrentlyActive ? 'Disattiva' : 'Attiva', style: TextStyle(color: isCurrentlyActive ? warningColor : successColor),),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFiltersRow(BuildContext context) {
    final screenType = breakpointOf(context);
    final bool desktopLayout =
        screenType == ScreenType.desktop || screenType == ScreenType.largeDesktop;
    final bool isAdmin = user.role == 'Admin';

    final tagDropdown = DropdownButtonFormField<String?>(
      value: selectedTagFilter,
      decoration: const InputDecoration(
        labelText: 'Tag',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Tutti i tag')),
        ...CourseTags.all.map((tag) => DropdownMenuItem(value: tag, child: Text(tag))),
      ],
      onChanged: (value) {
        selectedTagFilter = value;
        _applyFilters();
      },
    );

    final tipologiaDropdown = DropdownButtonFormField<TipologiaIscrizione?>(
      value: selectedTipologiaFilter,
      decoration: const InputDecoration(
        labelText: 'Tipologia abbonamento',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Tutte le tipologie')),
        ...TipologiaIscrizione.values.map((t) => DropdownMenuItem(
          value: t,
          child: Text(getTipologiaIscrizioneLabel(t)),
        )),
      ],
      onChanged: (value) {
        selectedTipologiaFilter = value;
        _applyFilters();
      },
    );

    final statoDropdown = DropdownButtonFormField<bool?>(
      value: activeFilter,
      decoration: const InputDecoration(
        labelText: 'Stato',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text('Tutti')),
        DropdownMenuItem(value: true, child: Text('Solo attivi')),
        DropdownMenuItem(value: false, child: Text('Solo disattivati')),
      ],
      onChanged: (value) {
        activeFilter = value;
        _applyFilters();
      },
    );

    final Widget? scadenzaAbbonamentoFilterDropdown = isAdmin
        ? DropdownButtonFormField<AbbonamentoScadenzaListFilter>(
            value: _abbonamentoScadenzaFilter,
            decoration: const InputDecoration(
              labelText: 'Scadenza abbonamento',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
            items: const [
              DropdownMenuItem(
                value: AbbonamentoScadenzaListFilter.tutti,
                child: Text('Tutti'),
              ),
              DropdownMenuItem(
                value: AbbonamentoScadenzaListFilter.inScadenzaProssimi30Giorni,
                child: Text('In scadenza (prossimi 30 gg)'),
              ),
              DropdownMenuItem(
                value: AbbonamentoScadenzaListFilter.senzaScadenza,
                child: Text('Senza scadenza'),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              _abbonamentoScadenzaFilter = value;
              _applyFilters();
            },
          )
        : null;

    if (desktopLayout) {
      return Row(
        children: [
          Expanded(child: tagDropdown),
          const SizedBox(width: 12),
          Expanded(child: tipologiaDropdown),
          const SizedBox(width: 12),
          Expanded(child: statoDropdown),
          if (scadenzaAbbonamentoFilterDropdown != null) ...[
            const SizedBox(width: 12),
            Expanded(child: scadenzaAbbonamentoFilterDropdown),
          ],
        ],
      );
    }

    // Mobile: filtri in un dropdown espandibile (mostra/nascondi)
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: ExpansionTile(
        initiallyExpanded: _filtersExpanded,
        onExpansionChanged: (expanded) {
          setState(() => _filtersExpanded = expanded);
        },
        title: Text(
          _filtersExpanded ? 'Nascondi filtri' : 'Mostra filtri',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: Icon(
          _filtersExpanded ? Icons.expand_less : Icons.expand_more,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tagDropdown,
                const SizedBox(height: 12),
                tipologiaDropdown,
                const SizedBox(height: 12),
                statoDropdown,
                if (scadenzaAbbonamentoFilterDropdown != null) ...[
                  const SizedBox(height: 12),
                  scadenzaAbbonamentoFilterDropdown,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCreateUser() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateUserPage(
          currentUserRole: user.role,
        ),
      ),
    );
    
    // Se l'utente è stato creato con successo, ricarica la lista
    if (result == true) {
      loadUsers();
    }
  }

  Widget _buildUsersTable({required bool showDesktopExtraColumns}) {
    if (displayedUsers.isEmpty && !isLoading) {
      return const Center(
        child: Text(
          'Nessun utente trovato',
          style: TextStyle(color: ghostColor),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final tableMinWidth = constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: tableMinWidth),
                child: DataTable(
                  columnSpacing: 20,
                  horizontalMargin: 0,
                  showCheckboxColumn: false,
                  columns: [
                    const DataColumn(label: Text('Nome')),
                    const DataColumn(label: Text('Email')),
                    if (showDesktopExtraColumns) ...[
                      const DataColumn(label: Text('Telefono')),
                      const DataColumn(label: Text('Scadenza abbonamento')),
                    ],
                    DataColumn(
                      columnWidth:
                          FixedColumnWidth(_userTableNarrowColumnWidth),
                      label: _userTableEllipsisText('Ruolo'),
                    ),
                    DataColumn(
                      columnWidth:
                          FixedColumnWidth(_userTableNarrowColumnWidth),
                      label: _userTableEllipsisText('Stato'),
                    ),
                    const DataColumn(label: Text('Azioni')),
                  ],
                  rows: displayedUsers.map((fitropeUser) {
                    return DataRow(
                      onSelectChanged: (_) => showUserDetails(fitropeUser),
                      cells: [
                        DataCell(Text('${fitropeUser.name} ${fitropeUser.lastName}')),
                        DataCell(Text(fitropeUser.email)),
                        if (showDesktopExtraColumns) ...[
                          DataCell(
                            _userTableEllipsisText(
                              _desktopTableTelefonoCell(fitropeUser),
                            ),
                          ),
                          DataCell(
                            _userTableEllipsisText(
                              _desktopTableScadenzaAbbonamentoCell(fitropeUser),
                            ),
                          ),
                        ],
                        DataCell(
                          Padding(
                            padding: _userTableNarrowCellPadding,
                            child: _userTableEllipsisText(fitropeUser.role),
                          ),
                        ),
                        DataCell(
                          Padding(
                            padding: _userTableNarrowCellPadding,
                            child: _userTableEllipsisText(
                              fitropeUser.isActive ? 'Attivo' : 'Disattivo',
                              style: TextStyle(
                                color: fitropeUser.isActive ? successColor : warningColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.info_outline),
                                tooltip: 'Dettagli',
                                onPressed: () => showUserDetails(fitropeUser),
                              ),
                              if (_canEditListedUser(fitropeUser))
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Modifica',
                                  onPressed: () =>
                                      showUserDetails(fitropeUser, openInEditMode: true),
                                ),
                              if (_canSendResetPasswordFromList() &&
                                  fitropeUser.email.trim().isNotEmpty)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.mark_email_unread_outlined),
                                  tooltip: 'Invia email reset password',
                                  onPressed: () => _showResetPasswordDialog(fitropeUser),
                                ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  fitropeUser.isActive ? Icons.block : Icons.check_circle,
                                  color: fitropeUser.isActive ? warningColor : successColor,
                                ),
                                tooltip: fitropeUser.isActive ? 'Disattiva' : 'Attiva',
                                onPressed: () => showToggleUserStatusDialog(fitropeUser),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
        if (hasMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(color: primaryColor),
            ),
          ),
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(
      converter: (store) => store.state,
      builder: (context, state) {
        final screenType = breakpointOf(context);
        final bool useUserTable = screenType != ScreenType.mobile;
        final bool desktopTableExtraColumns = isDesktop(context);

        return Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: pagePadding,
                right: pagePadding,
                bottom: pagePadding,
                top: pagePadding + MediaQuery.of(context).viewPadding.top,
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Image(image: AssetImage('assets/new_logo_only.png'), width: 30),
                      Expanded(
                        child: Text(
                          'Gestione Utenti',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 30,
                            color: onPrimaryColor,
                          ),
                        ),
                      ),
                      if (isDesktop(context))
                        const SizedBox(width: 30)
                      else
                        GestureDetector(
                          child: CircleAvatar(
                            backgroundColor: const Color.fromARGB(255, 96, 119, 246),
                            child: Text(user.name[0] + user.lastName[0]),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => UserDetailPage(user: user)),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    onChanged: filterUsers,
                    decoration: const InputDecoration(
                      hintText: 'Cerca utenti...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFiltersRow(context),
                  const SizedBox(height: 12),
                  if (useUserTable)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton.icon(
                        onPressed: _navigateToCreateUser,
                        icon: const Icon(Icons.person_add, color: Colors.white),
                        label: const Text('Crea Utente', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _navigateToCreateUser,
                        icon: const Icon(Icons.person_add, color: Colors.white),
                        label: const Text('Crea Utente', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Utenti (${filteredUsers.length})',
                      style: const TextStyle(
                        color: onPrimaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: useUserTable
                        ? _buildUsersTable(
                            showDesktopExtraColumns: desktopTableExtraColumns,
                          )
                        : (filteredUsers.isEmpty && !isLoading
                            ? const Center(
                                child: Text(
                                  'Nessun utente trovato',
                                  style: TextStyle(color: ghostColor),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: displayedUsers.length + (hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= displayedUsers.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      child: Center(
                                        child: CircularProgressIndicator(color: primaryColor),
                                      ),
                                    );
                                  }

                                  final user = displayedUsers[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListTile(
                                      leading: Stack(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: primaryLightColor,
                                            child: Text(
                                              '${user.name.isNotEmpty ? user.name[0] : ''}${user.lastName.isNotEmpty ? user.lastName[0] : ''}',
                                              style: const TextStyle(color: Colors.white),
                                            ),
                                          ),
                                          if (!user.isActive)
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.block,
                                                  color: Colors.white,
                                                  size: 12,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      title: Text('${user.name} ${user.lastName}'),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(user.email),
                                          Text('Ruolo: ${user.role}'),
                                        ],
                                      ),
                                      trailing: PopupMenuButton(
                                        shadowColor: onHintColor,
                                        surfaceTintColor: primaryColor,
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'details',
                                            child: Row(
                                              children: [
                                                Icon(Icons.info),
                                                SizedBox(width: 8),
                                                Text('Dettagli'),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  user.isActive ? Icons.block : Icons.check_circle,
                                                  color: user.isActive ? Colors.orange : Colors.green,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  user.isActive ? 'Disattiva' : 'Attiva',
                                                  style: TextStyle(
                                                    color: user.isActive
                                                        ? Colors.orange
                                                        : Colors.green,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        onSelected: (value) {
                                          switch (value) {
                                            case 'details':
                                              showUserDetails(user);
                                              break;
                                            case 'toggle':
                                              showToggleUserStatusDialog(user);
                                              break;
                                          }
                                        },
                                      ),
                                      onTap: () => showUserDetails(user),
                                    ),
                                  );
                                },
                              )),
                  ),
                ],
              ),
            ),
            if (isLoading) const Loader(),
          ],
        );
      },
    );
  }
}