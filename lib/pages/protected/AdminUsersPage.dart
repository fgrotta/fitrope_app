import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/authentication/toggleUserStatus.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/pages/protected/CreateUserPage.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<FitropeUser> users = [];
  List<FitropeUser> filteredUsers = [];
  TextEditingController searchController = TextEditingController();
  bool isLoading = true;
  late FitropeUser user;

  @override
  void initState() {
    super.initState();
    user = store.state.user!;
    loadUsers();

  }

  Future<void> loadUsers() async {
    setState(() {
      isLoading = true;
    });

    try {
      final usersList = await getUsers();

      setState(() {
        users = usersList;
        filteredUsers = usersList;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        isLoading = false;
      }); 
    }
  }

  void filterUsers(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredUsers = users;
      } else {
        filteredUsers = users.where((user) {
          final fullName = '${user.name} ${user.lastName}'.toLowerCase();
          final email = user.email.toLowerCase();
          final searchQuery = query.toLowerCase();
          return fullName.contains(searchQuery) || email.contains(searchQuery);
        }).toList();
      }
    });
  }

  void showUserDetails(FitropeUser user) async {
    final updatedUser = await Navigator.push<FitropeUser>(
      context,
      MaterialPageRoute(
        builder: (context) => UserDetailPage(user: user),
      ),
    );
    
    // Se l'utente è stato aggiornato, aggiorna la lista
    if (updatedUser != null) {
      setState(() {
        final index = users.indexWhere((u) => u.uid == updatedUser.uid);
        if (index != -1) {
          users[index] = updatedUser;
          // Ricarica anche la lista filtrata
          filterUsers(searchController.text);
        }
      });
    }
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
  
  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, AppState>(
      converter: (store) => store.state,
      builder: (context, state) {
        return Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      left: pagePadding,
                      right: pagePadding,
                      bottom: pagePadding,
                      top: pagePadding + MediaQuery.of(context).viewPadding.top,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Image(image: AssetImage('assets/new_logo_only.png'), width: 30,),
                        const Text('Gestione Utenti', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: onPrimaryColor),),
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
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pagePadding),
                    child: TextField(
                      controller: searchController,
                      onChanged: filterUsers,
                      decoration: const InputDecoration(
                        hintText: 'Cerca utenti...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pagePadding),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Utenti (${filteredUsers.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _navigateToCreateUser(),
                          icon: const Icon(Icons.person_add, color: Colors.white),
                          label: const Text('Crea Utente', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  ...filteredUsers.map((user) => Container(
                    margin: EdgeInsets.symmetric(horizontal: pagePadding, vertical: 4),
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
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          if (!user.isActive)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: EdgeInsets.all(2),
                                decoration: BoxDecoration(
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
                                  color: user.isActive ? Colors.orange : Colors.green
                                ),
                                SizedBox(width: 8),
                                Text(
                                  user.isActive ? 'Disattiva' : 'Attiva',
                                  style: TextStyle(
                                    color: user.isActive ? Colors.orange : Colors.green
                                  )
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
                  )).toList(),
                  if (filteredUsers.isEmpty && !isLoading)
                    Padding(
                      padding: EdgeInsets.all(pagePadding),
                      child: Center(
                        child: Text(
                          'Nessun utente trovato',
                          style: TextStyle(color: ghostColor),
                        ),
                      ),
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