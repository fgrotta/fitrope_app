import 'package:fitrope_app/api/authentication/deleteUser.dart';
import 'package:fitrope_app/components/loader.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/state/state.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers() async {
    setState(() {
      isLoading = true;
    });

    try {
      final usersCollection = FirebaseFirestore.instance.collection('users');
      final snapshot = await usersCollection.get();
      
      final usersList = snapshot.docs.map((doc) {
        final data = doc.data();
        return FitropeUser(
          uid: doc.id,
          email: data['email'] ?? '',
          name: data['name'] ?? '',
          lastName: data['lastName'] ?? '',
          role: data['role'] ?? 'User',
          courses: List<String>.from(data['courses'] ?? []),
          createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
        );
      }).toList();

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

  void showUserDetails(FitropeUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserDetailPage(user: user),
      ),
    );
  }



  void showDeleteUserDialog(FitropeUser user) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Elimina Utente'),
          content: Text('Sei sicuro di voler eliminare l\'utente ${user.name} ${user.lastName}? Questa azione non può essere annullata.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annulla'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await deleteUser(user.uid);
                  Navigator.pop(context);
                  loadUsers(); // Ricarica la lista
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Utente eliminato con successo')),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Errore durante l\'eliminazione')),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Elimina'),
            ),
          ],
        );
      },
    );
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
                    child: Text(
                      'Gestione Utenti',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: pagePadding),
                    child: TextField(
                      controller: searchController,
                      onChanged: filterUsers,
                      decoration: InputDecoration(
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
                    child: Text(
                      'Utenti (${filteredUsers.length})',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                      leading: CircleAvatar(
                        backgroundColor: primaryColor,
                        child: Text(
                          '${user.name.isNotEmpty ? user.name[0] : ''}${user.lastName.isNotEmpty ? user.lastName[0] : ''}',
                          style: TextStyle(color: Colors.white),
                        ),
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
                        itemBuilder: (context) => [
                          PopupMenuItem(
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
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Elimina', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) {
                          switch (value) {
                            case 'details':
                              showUserDetails(user);
                              break;
                            case 'delete':
                              showDeleteUserDialog(user);
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