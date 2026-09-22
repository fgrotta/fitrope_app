import 'package:fitrope_app/api/authentication/create_user.dart';
import 'package:fitrope_app/utils/subscription_plans.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CreateUserPage extends StatefulWidget {
  final String currentUserRole;

  const CreateUserPage({
    super.key,
    required this.currentUserRole,
  });

  @override
  State<CreateUserPage> createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _numeroTelefonoController = TextEditingController();

  String _selectedRole = 'User';
  String? _selectedPlanKey = SubscriptionPlans.trial.key;
  bool _isAnonymous = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _lastNameController.dispose();
    _numeroTelefonoController.dispose();
    super.dispose();
  }

  void _createUser() async {
    if (widget.currentUserRole != 'Admin') {
      SnackBarUtils.showErrorSnackBar(
        context,
        'Solo un Admin può creare utenti con un piano',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await createUser(
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        name: _nameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        role: _selectedRole,
        planKey: _selectedRole == 'User' ? _selectedPlanKey : null,
        isAnonymous: _isAnonymous,
        numeroTelefono: _numeroTelefonoController.text.trim().isNotEmpty
            ? _numeroTelefonoController.text.trim()
            : null,
      );
      if (!mounted) return;

      if (response.user != null) {
        SnackBarUtils.showSuccessSnackBar(
          context,
          'Utente creato con successo!',
        );
        Navigator.pop(context, true); // Ritorna true per indicare successo
      } else {
        SnackBarUtils.showErrorSnackBar(
          context,
          response.error ?? 'Errore durante la creazione dell\'utente',
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la creazione dell\'utente',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: onPrimaryColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Crea Nuovo Utente',
          style: TextStyle(color: onPrimaryColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(pagePadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Informazioni di base
              const Text(
                'Informazioni di Base',
                style: TextStyle(
                  color: onPrimaryColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Nome e Cognome
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome *',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Inserisci il nome';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Cognome *',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Inserisci il cognome';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Numero di Telefono (opzionale)
              TextFormField(
                controller: _numeroTelefonoController,
                decoration: const InputDecoration(
                  labelText: 'Numero di Telefono (opzionale)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    // Verifica che contenga solo numeri
                    if (!RegExp(r'^[0-9]+$').hasMatch(value.trim())) {
                      return 'Il numero di telefono deve contenere solo numeri';
                    } else if (value.trim().length != 10) {
                      return 'Il numero di telefono deve contenere esattamente 10 cifre';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email (opzionale)
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email (opzionale)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Lascia vuoto per creare un utente senza accesso',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(value.trim())) {
                      return 'Inserisci un\'email valida';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 24),

              // Ruolo e configurazioni
              const Text(
                'Configurazione Utente',
                style: TextStyle(
                  color: onPrimaryColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Ruolo (solo per Admin)
              if (widget.currentUserRole == 'Admin') ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Ruolo *',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'User', child: Text('User')),
                    DropdownMenuItem(value: 'Trainer', child: Text('Trainer')),
                    DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],

              if (_selectedRole == 'User') ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedPlanKey,
                  decoration: const InputDecoration(
                    labelText: 'Piano iniziale *',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: SubscriptionPlans.all
                      .map((plan) => DropdownMenuItem(
                          value: plan.key, child: Text(plan.displayName)))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPlanKey = value),
                  validator: (value) =>
                      value == null ? 'Seleziona un piano' : null,
                ),
                const SizedBox(height: 16),
              ],

              // Checkbox Anonimo
              CheckboxListTile(
                title: const Text('Utente Anonimo'),
                value: _isAnonymous,
                onChanged: (value) {
                  setState(() {
                    _isAnonymous = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: primaryColor,
              ),
              const SizedBox(height: 16),

              const SizedBox(height: 32),

              // Pulsanti
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: onPrimaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Annulla',
                          style: TextStyle(color: onPrimaryColor)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _createUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Crea Utente',
                              style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
