import 'package:fitrope_app/api/authentication/updateUser.dart';
import 'package:fitrope_app/api/authentication/toggleUserStatus.dart';
import 'package:fitrope_app/authentication/logout.dart';
import 'package:fitrope_app/authentication/resetPassword.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:fitrope_app/utils/certificato_helper.dart';
import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class UserDetailPage extends StatefulWidget {
  final FitropeUser user;

  const UserDetailPage({super.key, required this.user});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  bool isEditing = false;
  late TextEditingController nameController;
  late TextEditingController lastNameController;
  late TextEditingController numeroTelefonoController;
  late TextEditingController entrateDisponibiliController;
  late TextEditingController entrateSettimanaliController;
  late String selectedRole;
  late TipologiaIscrizione? selectedTipologiaIscrizione;
  late DateTime? selectedFineIscrizione;
  late bool selectedIsActive;
  late bool selectedIsAnonymous;
  late DateTime? selectedCertificatoScadenza;
  String? errorMsg;
  List<Course> allCourses = [];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.user.name);
    lastNameController = TextEditingController(text: widget.user.lastName);
    numeroTelefonoController = TextEditingController(text: widget.user.numeroTelefono ?? '');
    entrateDisponibiliController = TextEditingController(text: widget.user.entrateDisponibili?.toString() ?? '');
    entrateSettimanaliController = TextEditingController(text: widget.user.entrateSettimanali?.toString() ?? '');
    selectedRole = widget.user.role;
    selectedTipologiaIscrizione = widget.user.tipologiaIscrizione;
    selectedFineIscrizione = widget.user.fineIscrizione?.toDate();
    selectedIsActive = widget.user.isActive;
    selectedIsAnonymous = widget.user.isAnonymous;
    selectedCertificatoScadenza = widget.user.certificatoScadenza?.toDate();
    // print(widget.user.isAnonymous);
    loadCourses();
  }

  Future<void> loadCourses() async {
    try {
      final courses = await getAllCourses();
      setState(() {
        allCourses = courses;
      });
    } catch (e) {
      print('Error loading courses: $e');
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    lastNameController.dispose();
    numeroTelefonoController.dispose();
    entrateDisponibiliController.dispose();
    entrateSettimanaliController.dispose();
    super.dispose();
  }

  void toggleEdit() {
    setState(() {
      isEditing = !isEditing;
      if (!isEditing) {
        // Reset to original values if canceling edit
        nameController.text = widget.user.name;
        lastNameController.text = widget.user.lastName;
        numeroTelefonoController.text = widget.user.numeroTelefono ?? '';
        entrateDisponibiliController.text = widget.user.entrateDisponibili?.toString() ?? '';
        entrateSettimanaliController.text = widget.user.entrateSettimanali?.toString() ?? '';
        selectedRole = widget.user.role;
        selectedTipologiaIscrizione = widget.user.tipologiaIscrizione;
        selectedFineIscrizione = widget.user.fineIscrizione?.toDate();
        selectedIsActive = widget.user.isActive;
        selectedIsAnonymous = widget.user.isAnonymous;
        selectedCertificatoScadenza = widget.user.certificatoScadenza?.toDate();
        errorMsg = null;
      }
    });
  }

  List<Map<String, String>> getUserCourses() {
    List<Map<String, String>> userCourses = [];
    
    var userCoursesIds = widget.user.courses.length > 10 ? widget.user.courses.sublist(widget.user.courses.length - 10) : widget.user.courses;
    for (String courseId in userCoursesIds) {
      Course? course = allCourses.where((c) => c.id == courseId).firstOrNull;
      if (course != null) {
        String courseName = course.name;
        String courseDate = DateFormat('dd/MM/yyyy').format(course.startDate.toDate());
        userCourses.add({
          'name': courseName,
          'date': courseDate,
        });
      }
    }
    
    // Ordina per data (più recenti prima) e prendi solo gli ultimi 10
    userCourses.sort((a, b) => DateFormat('dd/MM/yyyy').parse(b['date']!).compareTo(DateFormat('dd/MM/yyyy').parse(a['date']!)));
    return userCourses;
  }

  Future<void> saveChanges() async {
    final name = nameController.text.trim();
    final lastName = lastNameController.text.trim();
    final numeroTelefono = numeroTelefonoController.text.trim();
    final entrateDisponibili = int.tryParse(entrateDisponibiliController.text.trim());
    final entrateSettimanali = int.tryParse(entrateSettimanaliController.text.trim());
    
    if (name.isEmpty || lastName.isEmpty) {
      setState(() { errorMsg = 'Compila tutti i campi obbligatori'; });
      return;
    }
  
    if (entrateSettimanali != null && entrateSettimanali < 0) {
      setState(() { errorMsg = 'Le entrate settimanali non possono essere negative'; });
      return;
    }

    // Validazione numero di telefono
    if (numeroTelefono.isNotEmpty) {
      // Verifica che contenga solo numeri
      if (!RegExp(r'^[0-9]+$').hasMatch(numeroTelefono)) {
        setState(() { errorMsg = 'Il numero di telefono deve contenere solo numeri'; });
        return;
      } else if (numeroTelefono.length != 10) {
        setState(() { errorMsg = 'Il numero di telefono deve contenere esattamente 10 cifre'; });
        return;
      }
    }

    try {
      await updateUser(
        uid: widget.user.uid,
        name: name,
        lastName: lastName,
        role: selectedRole,
        tipologiaIscrizione: selectedTipologiaIscrizione,
        entrateDisponibili: entrateDisponibili,
        entrateSettimanali: entrateSettimanali,
        fineIscrizione: selectedFineIscrizione,
        isActive: selectedIsActive,
        isAnonymous: selectedIsAnonymous,
        certificatoScadenza: selectedCertificatoScadenza,
        numeroTelefono: numeroTelefono.isNotEmpty ? numeroTelefono : null,
      );

      // Crea un nuovo oggetto utente con i dati aggiornati
      final updatedUser = FitropeUser(
        uid: widget.user.uid,
        email: widget.user.email,
        name: name,
        lastName: lastName,
        role: selectedRole,
        courses: widget.user.courses,
        tipologiaIscrizione: selectedTipologiaIscrizione,
        entrateDisponibili: entrateDisponibili,
        entrateSettimanali: entrateSettimanali,
        fineIscrizione: selectedFineIscrizione != null 
            ? Timestamp.fromDate(DateTime(selectedFineIscrizione!.year, selectedFineIscrizione!.month, selectedFineIscrizione!.day, 23, 59))
            : null,
        isActive: selectedIsActive,
        isAnonymous: selectedIsAnonymous,
        createdAt: widget.user.createdAt,
        certificatoScadenza: selectedCertificatoScadenza != null 
            ? Timestamp.fromDate(DateTime(selectedCertificatoScadenza!.year, selectedCertificatoScadenza!.month, selectedCertificatoScadenza!.day, 23, 59))
            : null,
        numeroTelefono: numeroTelefono.isNotEmpty ? numeroTelefono : null,
      );

      setState(() {
        isEditing = false;
        errorMsg = null;
      });

      // Notifica la pagina precedente del cambiamento
      Navigator.pop(context, updatedUser);

      SnackBarUtils.showSuccessSnackBar(
        context,
        'Utente aggiornato con successo',
      );
    } catch (e) {
      setState(() { errorMsg = 'Errore durante l\'aggiornamento'; });
    }
  }

  void showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          title: const Text('Conferma Logout'),
          content: const Text('Sei sicuro di voler effettuare il logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla', style: TextStyle(color: onPrimaryColor),),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await signOut();
                  Navigator.pop(context); // Chiudi la modale
                  logoutRedirect(context); // Reindirizza al login
                } catch (e) {
                  Navigator.pop(context);
                  SnackBarUtils.showErrorSnackBar(
                    context,
                    'Errore durante il logout',
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: warningColor),
              child: const Text('Logout', style: TextStyle(color: warningColor, fontWeight: FontWeight.bold),),
            ),
          ],
        );
      },
    );
  }

  void showDeleteAccountConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          title: const Text('Cancellazione Account'),
          content: const Text(
            'Sei sicuro di voler Disattivare il tuo account?\n\n'
            'I tuoi dati verranno mantenuti ma non sarai più in grado di utilizzare l\'applicazione.\n\n'
            'Se cambi idea, contatta l\'amministratore per riattivare il tuo account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla', style: TextStyle(color: onPrimaryColor),),
            ),
            TextButton(
              onPressed: () async {
                try {
                  // Disattiva l'account dell'utente
                  await toggleUserStatus(widget.user.uid, false);
                  Navigator.pop(context); // Chiudi la modale
                  
                  // Mostra messaggio di conferma
                  SnackBarUtils.showSuccessSnackBar(
                    context,
                    'Account disattivato con successo. Sei stato sloggato.',
                  );
                  
                  // Effettua il logout immediatamente
                  await signOut();
                  // Verifica se il context è ancora valido prima di navigare
                  if (context.mounted) {
                    logoutRedirect(context);
                  }
                } catch (e) {
                  Navigator.pop(context);
                  SnackBarUtils.showErrorSnackBar(
                    context,
                    'Errore durante la cancellazione dell\'account',
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancella Account', style: TextStyle(color: errorColor, fontWeight: FontWeight.bold),),
            ),
          ],
        );
      },
    );
  }

  void showResetPasswordConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          title: const Text('Invia Email Reset Password'),
          content: Text(
            'Sei sicuro di voler inviare un\'email di reset password a ${widget.user.email}?\n\n'
            'L\'utente riceverà un\'email con le istruzioni per reimpostare la propria password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla', style: TextStyle(color: onPrimaryColor),),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await resetPassword(widget.user.email);
                  Navigator.pop(context); // Chiudi la modale
                  
                  SnackBarUtils.showSuccessSnackBar(
                    context,
                    'Email di reset password inviata con successo a ${widget.user.email}',
                  );
                } catch (e) {
                  Navigator.pop(context);
                  SnackBarUtils.showErrorSnackBar(
                    context,
                    'Errore durante l\'invio dell\'email di reset password',
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: primaryColor),
              child: const Text('Invia Email', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),),
            ),
          ],
        );
      },
    );
  }

  bool _canViewUser() {
    final currentUser = store.state.user;
    if (currentUser == null) return false;
    
    // L'utente può sempre vedere il suo profilo
    if (currentUser.uid == widget.user.uid) {
      return true;
    }
    
    // Admin può vedere tutti gli utenti
    if (currentUser.role == 'Admin') {
      return true;
    }
    
    // Trainer può vedere solo utenti con ruolo User
    if (currentUser.role == 'Trainer') {
      return widget.user.role == 'User';
    }
    
    // User può vedere solo il suo profilo (già controllato sopra)
    return false;
  }

  bool _canEditUser() {
    final currentUser = store.state.user;
    if (currentUser == null) return false;
    // L'utente può sempre modificare il suo profilo
    if (currentUser.uid == widget.user.uid || currentUser.role == 'Admin') {
      return true;
    }
    // Trainer può modificare solo Nome e Cognome di utenti con ruolo User
    if (currentUser.role == 'Trainer') {
      return widget.user.role == 'User';
    }
    // User può modificare solo il suo profilo (già controllato sopra)
    return false;
  }

  bool _canEditSpecificField(String fieldName) {
    final currentUser = store.state.user;
  
    if (currentUser == null) return false;
    // Admin può modificare tutti i campi
    if (currentUser.role == 'Admin') {
      return true;
    }
    // Trainer può modificare solo Nome, Cognome e Numero di Telefono di utenti con ruolo User
    if (currentUser.role == 'Trainer' && widget.user.role == 'User') {
      return fieldName == 'Nome' || fieldName == 'Cognome' || fieldName == 'Numero di Telefono' || fieldName == 'Anonimo';
    }

    // Il campo Stato,Tipologia, Entrate Disponibili, Entrate Settimanali, Ruolo, Fine Iscrizione e Certificato sono gestiti solo dagli Admin
    if (fieldName == 'Stato' || fieldName == 'Tipologia' || fieldName == 'Entrate Disponibili' || 
        fieldName == 'Entrate Settimanali' || fieldName == 'Fine Iscrizione' || fieldName == 'Ruolo' || fieldName == 'Certificato') {
      return currentUser.role == 'Admin';
    }
    return true;
  }

  String _getValidRoleForDropdown() {
    // Se l'utente corrente non è Admin e selectedRole è Trainer, 
    // restituisci 'User' come fallback
    if (store.state.user?.role != 'Admin' && selectedRole == 'Trainer') {
      return 'User';
    }
    return selectedRole;
  }

  String _getCertificatoText() {
    if (widget.user.certificatoScadenza == null) {
      return 'Non impostato';
    }
    
    final dataFormattata = CertificatoHelper.formatDataScadenza(widget.user.certificatoScadenza);
    final stato = CertificatoHelper.getStatoCertificato(widget.user.certificatoScadenza);
    
    return '$dataFormattata ($stato)';
  }

  @override
  Widget build(BuildContext context) {
    // Controlla se l'utente corrente può vedere questo utente
    if (!_canViewUser()) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Accesso Negato'),
        ),
        body: const Center(
          child: Text(
            'Non hai i permessi per visualizzare i dettagli di questo utente.',
            style: TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: Text(store.state.user?.uid == widget.user.uid ? 'Il Mio Profilo' : 'Dettagli Utente'),
        actions: [
          if (!isEditing && _canEditUser()) ...[            
            // Pulsante Cancella Account solo per il proprio profilo
            if (store.state.user?.uid == widget.user.uid)
              IconButton(
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                onPressed: showDeleteAccountConfirmation,
                tooltip: 'Cancella Account',
              ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: toggleEdit,
            ),
          ],
          if (isEditing) ...[
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: saveChanges,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: toggleEdit,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con avatar e nome
            Center(
              child: Column(
                children: [
                  Text(
                    '${widget.user.name} ${widget.user.lastName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: primaryLightColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          widget.user.name + ' ' + widget.user.lastName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!widget.user.isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.block, color: Colors.white, size: 16),
                              SizedBox(width: 4),
                              Text(
                                'Disattivato',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Sezione informazioni personali
            _buildSection(
              'Informazioni Personali',
              [
                _buildInfoRow('Nome', widget.user.name, nameController, _canEditSpecificField('Nome') && isEditing),
                _buildInfoRow('Cognome', widget.user.lastName, lastNameController, _canEditSpecificField('Cognome') && isEditing),
                _buildInfoRow('Numero di Telefono', widget.user.numeroTelefono ?? 'Non impostato', numeroTelefonoController, _canEditSpecificField('Numero di Telefono') && isEditing),
                _buildInfoRow('Email', widget.user.email, null, false),
                if (isAdmin)
                _buildInfoRow('Ruolo', widget.user.role, null, _canEditSpecificField('Ruolo') && isEditing, isDropdown: true),
                _buildInfoRow('Certificato Medico', _getCertificatoText(), null, _canEditSpecificField('Certificato') && isEditing, isCertificatoDatePicker: true),
                // Campo Stato visibile solo agli Admin
                if (isAdmin)
                  _buildInfoRow('Stato', widget.user.isActive ? 'Attivo' : 'Disattivato', null, _canEditSpecificField('Stato') && isEditing, isStatusDropdown: true),
                _buildInfoRow('Anonimo', widget.user.isAnonymous ? 'Si' : 'No', null, _canEditSpecificField('Anonimo') && isEditing, isAnonymousDropdown: true),
                // Pulsante per inviare email di reset password (solo per Admin)
                if (isAdmin) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: showResetPasswordConfirmation,
                      icon: const Icon(Icons.email, color: Colors.white),
                      label: const Text(
                        'Invia Email Reset Password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Sezione piano di iscrizione
            _buildSection(
              'Piano di Iscrizione',
              [
                _buildInfoRow('Tipologia', _getTipologiaLabel(widget.user.tipologiaIscrizione), null, _canEditSpecificField('Tipologia') && isEditing, isTipologiaDropdown: true),
                if (widget.user.tipologiaIscrizione == TipologiaIscrizione.PACCHETTO_ENTRATE || isAdmin) ...[
                  _buildInfoRow('Entrate Disponibili', widget.user.entrateDisponibili?.toString() ?? '0', entrateDisponibiliController, _canEditSpecificField('Entrate Disponibili') && isEditing),                  
                ],
                _buildInfoRow('Entrate Settimanali', widget.user.entrateSettimanali?.toString() ?? '0', entrateSettimanaliController, _canEditSpecificField('Entrate Settimanali') && isEditing),
                _buildInfoRow('Fine Iscrizione', widget.user.fineIscrizione != null ? DateFormat('dd/MM/yyyy').format(widget.user.fineIscrizione!.toDate()) : 'Non impostata', null, _canEditSpecificField('Fine Iscrizione') && isEditing, isDatePicker: true),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Sezione informazioni account
            _buildSection(
              'Informazioni Account',
              [
                _buildInfoRow('Data Registrazione', DateFormat('dd/MM/yyyy HH:mm').format(widget.user.createdAt), null, false),
                _buildInfoRow('Corsi Iscritti', '${widget.user.courses.length}', null, false),
              ],
            ),
            
            if (widget.user.courses.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSection(
                'Ultime 10 iscrizioni',
                getUserCourses().map((courseInfo) => 
                  _buildInfoRow(courseInfo['name']!, courseInfo['date']!, null, false)
                ).toList(),
              ),
            ],
            //TODO aggiungere corsi fatti nel caso sia Trainer
            if (errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    errorMsg!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            
            // Pulsante Logout (solo per il proprio profilo)
            if (store.state.user?.uid == widget.user.uid) ...[
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: showLogoutConfirmation,
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get isAdmin => store.state.user?.role == 'Admin';

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: outlineColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryLightColor,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, TextEditingController? controller, bool isEditable, {bool isDropdown = false, bool isTipologiaDropdown = false, bool isDatePicker = false, bool isStatusDropdown = false, bool isAnonymousDropdown = false, bool isCertificatoDatePicker = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: primaryLightColor,
              ),
            ),
          ),
          Expanded(
            child: isEditable && controller != null
                ? TextField(
                    controller: controller,
                    keyboardType: label == 'Numero di Telefono (opzionale)' ? TextInputType.phone : TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    inputFormatters: label == 'Numero di Telefono' ? [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ] : null,
                    onChanged: label == 'Numero di Telefono' ? (value) {
                      // Validazione in tempo reale per il numero di telefono
                      if (value.isNotEmpty) {
                        if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                          // Non mostriamo errore in tempo reale, solo durante il salvataggio
                        }
                      }
                    } : null,
                  )
                : isEditable && isDropdown
                    ? DropdownButtonFormField<String>(
                        value: _getValidRoleForDropdown(),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'User',
                            child: Text('User'),
                          ),
                          // Solo gli admin possono assegnare il ruolo Trainer
                          if (isAdmin)
                            DropdownMenuItem(
                              value: 'Trainer',
                              child: Text('Trainer'),
                            ),
                          DropdownMenuItem(
                            value: 'Admin',
                            child: Text('Admin'),
                          ),
                        ],
                        onChanged: (newValue) {
                          setState(() {
                            selectedRole = newValue!;
                          });
                        },
                      )
                    : isEditable && isTipologiaDropdown
                        ? DropdownButtonFormField<String>(
                            value: selectedTipologiaIscrizione?.toString().split('.').last,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Nessuna', style: TextStyle(color: onPrimaryColor),)),
                              ...TipologiaIscrizione.values.map((tipologia) {
                                return DropdownMenuItem(
                                  value: tipologia.toString().split('.').last,
                                  child: Text(_getTipologiaLabel(tipologia)),
                                );
                              }),
                            ],
                            onChanged: (newValue) {
                              setState(() {
                                selectedTipologiaIscrizione = newValue != null 
                                    ? TipologiaIscrizione.values.where((e) => e.toString().split('.').last == newValue).firstOrNull
                                    : null;
                              });
                            },
                          )
                  : isEditable && isDatePicker
                            ? InkWell(
                                onTap: () async {
                                  final DateTime now = DateTime.now();
                                  final DateTime initialDate = selectedFineIscrizione != null && selectedFineIscrizione!.isAfter(now)
                                      ? selectedFineIscrizione!
                                      : now.subtract(const Duration(days: 180));
                                  
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: initialDate,
                                    firstDate: now,
                                    lastDate: now.add(const Duration(days: 365 * 2)),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      selectedFineIscrizione = picked;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        selectedFineIscrizione != null 
                                            ? DateFormat('dd/MM/yyyy').format(selectedFineIscrizione!)
                                            : 'Seleziona data',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const Icon(Icons.calendar_today),
                                    ],
                                  ),
                                ),
                              )
                            : isEditable && isStatusDropdown
                            ? DropdownButtonFormField<bool>(
                                value: selectedIsActive,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: true,
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.green),
                                        SizedBox(width: 8),
                                        Text('Attivo', style: TextStyle(color: onPrimaryColor),),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: false,
                                    child: Row(
                                      children: [
                                        Icon(Icons.block, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Disattivato'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (newValue) {
                                  setState(() {
                                    selectedIsActive = newValue!;
                                  });
                                },
                              )
                            : isEditable && isAnonymousDropdown
                            ? DropdownButtonFormField<bool>(
                                value: selectedIsAnonymous,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: false,
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, color: Colors.green),
                                        SizedBox(width: 8),
                                        Text('No'),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: true,
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility_off, color: Colors.grey),
                                        SizedBox(width: 8),
                                        Text('Sì'),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (newValue) {
                                  setState(() {
                                    selectedIsAnonymous = newValue!;
                                  });
                                },
                              )
                            : isEditable && isCertificatoDatePicker
                            ? InkWell(
                                onTap: () async {
                                  final DateTime now = DateTime.now();
                                  final DateTime initialDate = selectedCertificatoScadenza != null && selectedCertificatoScadenza!.isAfter(now)
                                      ? selectedCertificatoScadenza!
                                      : now;
                                  
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: initialDate,
                                    firstDate: now.subtract(const Duration(days: 180)),
                                    lastDate: now.add(const Duration(days: 400)), 
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      selectedCertificatoScadenza = picked;
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        selectedCertificatoScadenza != null 
                                            ? DateFormat('dd/MM/yyyy').format(selectedCertificatoScadenza!)
                                            : 'Seleziona data',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const Icon(Icons.calendar_today),
                                    ],
                                  ),
                                ),
                              )
                            : Text(
                                value,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: label == 'Certificato Medico' && widget.user.certificatoScadenza != null
                                      ? CertificatoHelper.getColoreScadenza(widget.user.certificatoScadenza)
                                      : null,
                                ),
                              ),
          ),
        ],
      ),
    );
  }

  String _getTipologiaLabel(TipologiaIscrizione? tipologia) {
    if (tipologia == null) return 'Nessuna';
    switch (tipologia) {
      case TipologiaIscrizione.PACCHETTO_ENTRATE:
        return 'Pacchetto Entrate';
      case TipologiaIscrizione.ABBONAMENTO_MENSILE:
        return 'Abbonamento Mensile';
      case TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE:
        return 'Abbonamento Trimestrale';
      case TipologiaIscrizione.ABBONAMENTO_SEMESTRALE:
        return 'Abbonamento Semestrale';
      case TipologiaIscrizione.ABBONAMENTO_ANNUALE:
        return 'Abbonamento Annuale';
      case TipologiaIscrizione.ABBONAMENTO_PROVA:
        return 'Lezione di Prova';
    }
  }
}