import 'package:fitrope_app/api/authentication/createUser.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

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
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _entrateDisponibiliController = TextEditingController(text: '1');
  final _entrateSettimanaliController = TextEditingController(text: '0');
  
  String _selectedRole = 'User';
  TipologiaIscrizione? _selectedTipologia = TipologiaIscrizione.ABBONAMENTO_PROVA;
  int? _entrateDisponibili = 1;
  int? _entrateSettimanali = 0;
  bool _isAnonymous = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
   
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _lastNameController.dispose();
    _entrateDisponibiliController.dispose();
    _entrateSettimanaliController.dispose();
    super.dispose();
  }

  void _createUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await createUser(
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        password: _passwordController.text.isEmpty ? null : _passwordController.text,
        name: _nameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        role: _selectedRole,
        tipologiaIscrizione: _selectedTipologia,
        entrateDisponibili: _entrateDisponibili,
        entrateSettimanali: _entrateSettimanali,
        isAnonymous: _isAnonymous,
      );

      if (response.user != null) {
        Navigator.pop(context, true); // Ritorna true per indicare successo
        SnackBarUtils.showSuccessSnackBar(
          context,
          'Utente creato con successo!',
        );
      } else {
        SnackBarUtils.showErrorSnackBar(
          context,
          response.error ?? 'Errore durante la creazione dell\'utente',
        );
      }
    } catch (e) {
      SnackBarUtils.showErrorSnackBar(
        context,
        'Errore durante la creazione dell\'utente',
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
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
                        if (value == null || value.isEmpty) {
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
                        if (value == null || value.isEmpty) {
                          return 'Inserisci il cognome';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
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
                  if (value != null && value.isNotEmpty) {
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                      return 'Inserisci un\'email valida';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password (opzionale)
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password (opzionale)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Lascia vuoto per creare un utente senza accesso',
                ),
                obscureText: true,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    if (value.length < 6) {
                      return 'La password deve essere di almeno 6 caratteri';
                    }
                  }
                  return null;
                },
              ),
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
                  value: _selectedRole,
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

              // Tipologia Iscrizione
              DropdownButtonFormField<TipologiaIscrizione?>(
                value: _selectedTipologia,
                decoration: const InputDecoration(
                  labelText: 'Tipologia Iscrizione',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Abbonamento Prova selezionato di default',
                ),
                items: [
                  const DropdownMenuItem<TipologiaIscrizione?>(
                    value: null,
                    child: Text('Nessuna'),
                  ),
                  ...TipologiaIscrizione.values.map((tipologia) {
                    String displayName;
                    switch (tipologia) {
                      case TipologiaIscrizione.PACCHETTO_ENTRATE:
                        displayName = 'Pacchetto Entrate';
                        break;
                      case TipologiaIscrizione.ABBONAMENTO_MENSILE:
                        displayName = 'Abbonamento Mensile';
                        break;
                      case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE:
                        displayName = 'Abbonamento Trimestrale';
                        break;
                      case TipologiaIscrizione.ABBONAMENTO_SEMESTRALE:
                        displayName = 'Abbonamento Semestrale';
                        break;
                      case TipologiaIscrizione.ABBONAMENTO_ANNUALE:
                        displayName = 'Abbonamento Annuale';
                        break;
                      case TipologiaIscrizione.ABBONAMENTO_PROVA:
                        displayName = 'Lezione di Prova';
                        break;
                    }
                    return DropdownMenuItem<TipologiaIscrizione?>(
                      value: tipologia,
                      child: Text(displayName),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTipologia = value;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Entrate Disponibili
              TextFormField(
                controller: _entrateDisponibiliController,
                decoration: const InputDecoration(
                  labelText: 'Entrate Disponibili',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Default: 1',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _entrateDisponibili = value.isEmpty ? null : int.tryParse(value);
                },
              ),
              const SizedBox(height: 16),

              // Entrate Settimanali
              TextFormField(
                controller: _entrateSettimanaliController,
                decoration: const InputDecoration(
                  labelText: 'Entrate Settimanali',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  helperText: 'Default: 0',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _entrateSettimanali = value.isEmpty ? null : int.tryParse(value);
                },
              ),
              const SizedBox(height: 16),

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
              const SizedBox(height: 32),

              // Pulsanti
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: onPrimaryColor),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Annulla', style: TextStyle(color: onPrimaryColor)),
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Crea Utente', style: TextStyle(color: Colors.white)),
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
