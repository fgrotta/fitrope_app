import 'package:fitrope_app/api/courses/getCourses.dart';
import 'package:fitrope_app/api/courses/subscribeToCourse.dart';
import 'package:fitrope_app/api/getUserData.dart';
import 'package:fitrope_app/components/course_preview_card.dart';
import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/state/actions.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/api/authentication/getUsers.dart';
import 'package:fitrope_app/api/authentication/getUsersWithExpiringCertificates.dart';
import 'package:fitrope_app/api/authentication/getUsersWithExpiringSubscriptions.dart';
import 'package:fitrope_app/utils/getCourseState.dart';
import 'package:fitrope_app/utils/getTipologiaIscrizioneLabel.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';
import 'package:fitrope_app/utils/certificato_helper.dart';
import 'package:fitrope_app/utils/abbonamento_helper.dart';
import 'package:fitrope_app/utils/certificate_refresh_manager.dart';
import 'package:fitrope_app/components/course_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late FitropeUser user;
  List<Course> allCourses = [];
  List<FitropeUser> trainers = [];
  List<FitropeUser> utentiConCertificatoInScadenza = [];
  bool isLoadingCertificati = false;
  List<FitropeUser> utentiConAbbonamentoInScadenza = [];
  bool isLoadingAbbonamenti = false;

  @override
  void initState() {
    user = store.state.user!;
    getTrainers().then((List<FitropeUser> response) {
      setState(() {
        trainers = response;
      });
    });
    getAllCourses().then((List<Course> response) {
      setState(() {
        if(mounted) {
          allCourses = response;
          store.dispatch(SetAllCoursesAction(response));
        }
      });
    });
    
    // Carica utenti con certificati in scadenza se l'utente è Admin
    if (user.role == 'Admin') {
      _loadUtentiConCertificatoInScadenza();
      _loadUtentiConAbbonamentoInScadenza();
      
      // Registra il listener per il refresh automatico
      CertificateRefreshManager().addListener(_loadUtentiConCertificatoInScadenza);
      CertificateRefreshManager().addListener(_loadUtentiConAbbonamentoInScadenza);
    }
    
    super.initState();
  }

  @override
  void dispose() {
    // Rimuove il listener per evitare memory leak
    if (user.role == 'Admin') {
      CertificateRefreshManager().removeListener(_loadUtentiConCertificatoInScadenza);
      CertificateRefreshManager().removeListener(_loadUtentiConAbbonamentoInScadenza);
    }
    super.dispose();
  }


  // Funzione ottimizzata per caricare solo gli utenti con certificati in scadenza
  Future<void> _loadUtentiConCertificatoInScadenza() async {
    if (user.role != 'Admin') return;

    setState(() {
      isLoadingCertificati = true;
    });

    try {
      final utenti = await getUsersWithExpiringCertificates();
      
      setState(() {
        utentiConCertificatoInScadenza = utenti;
        isLoadingCertificati = false;
      });
    } catch (e) {
      print('Errore nel caricamento utenti con certificati in scadenza: $e');
      setState(() {
        isLoadingCertificati = false;
      });
    }
  }

  // Funzione ottimizzata per caricare solo gli utenti con abbonamenti in scadenza
  Future<void> _loadUtentiConAbbonamentoInScadenza() async {
    if (user.role != 'Admin') return;

    setState(() {
      isLoadingAbbonamenti = true;
    });

    try {
      final utenti = await getUsersWithExpiringSubscriptions();
      
      setState(() {
        utentiConAbbonamentoInScadenza = utenti;
        isLoadingAbbonamenti = false;
      });
    } catch (e) {
      print('Errore nel caricamento utenti con abbonamenti in scadenza: $e');
      setState(() {
        isLoadingAbbonamenti = false;
      });
    }
  }

  // Funzione per aggiornare i corsi e lo stato utente
  void refreshCourses() {
    getAllCourses().then((List<Course> response) {
      if(mounted) {
        setState(() {
          allCourses = response;
          store.dispatch(SetAllCoursesAction(response));
        });
      }
    });
    
    // Aggiorna anche lo stato utente per riflettere le modifiche
    if (store.state.user != null) {
      getUserData(user.uid).then((userData) {
        if (userData != null && mounted) {
          setState(() {
            user = FitropeUser.fromJson(userData);
          });
          store.dispatch(SetUserAction(user));
        }
      });
    }

    // Ricarica anche i certificati in scadenza se l'utente è Admin
    if (user.role == 'Admin') {
      _loadUtentiConCertificatoInScadenza();
      _loadUtentiConAbbonamentoInScadenza();
    }
  }

  // Callback per l'iscrizione
  void onSubscribe(Course course) {
    print('🔄 Iscrizione al corso: ${course.name}');
    subscribeToCourse(course.uid, user.uid).then((_) {
      print('✅ Iscrizione completata');
      refreshCourses();
    }).catchError((e) {
      print('❌ Errore durante l\'iscrizione: $e');
      // Mostra snackbar di errore
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante l\'iscrizione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  // Callback per la disiscrizione
  void onUnsubscribe(Course course) {
    print('🔄 Disiscrizione dal corso: ${course.name}');
    // Usa il nuovo sistema di disiscrizione intelligente
    CourseUnsubscribeHelper.handleUnsubscribe(course, user, context).then((success) {
      if (success) {
        print('✅ Disiscrizione completata');
        refreshCourses();
        
        // Mostra messaggio di successo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disiscrizione completata con successo'),
              backgroundColor: successColor,
            ),
          );
        }
      } else {
        print('❌ Disiscrizione annullata dall\'utente');
      }
    }).catchError((e) {
      print('❌ Errore durante la disiscrizione: $e');
      // Mostra snackbar di errore
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante la disiscrizione: $e'),
            backgroundColor: errorColor,
          ),
        );
      }
    });
  }

  Widget renderSubscriptionCard() {
    if(
      user.tipologiaIscrizione != TipologiaIscrizione.ABBONAMENTO_MENSILE &&
      user.tipologiaIscrizione != TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE &&
      user.tipologiaIscrizione != TipologiaIscrizione.ABBONAMENTO_SEMESTRALE &&
      user.tipologiaIscrizione != TipologiaIscrizione.ABBONAMENTO_ANNUALE &&
      user.tipologiaIscrizione != TipologiaIscrizione.PACCHETTO_ENTRATE &&
      user.tipologiaIscrizione != TipologiaIscrizione.ABBONAMENTO_PROVA
    ) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 20, bottom: 10),
            width: double.infinity,
            child: const Text('Il mio abbonamento', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
          ),
          const SizedBox(height: 20,),
          const Text('Nessun abbonamento disponibile', style: TextStyle(color: onPrimaryColor),),
          const SizedBox(height: 30,),
        ],
      );
    }

    bool isExpired = false;
    int today = DateTime.now().millisecondsSinceEpoch;

    if(
      (user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_MENSILE ||
      user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_TRIMESTRALE ||
      user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_SEMESTRALE ||
      user.tipologiaIscrizione == TipologiaIscrizione.ABBONAMENTO_ANNUALE) &&
      user.fineIscrizione != null && 
      today > user.fineIscrizione!.toDate().millisecondsSinceEpoch
    ) {
      isExpired = true;
    }

    // Controlla se il certificato è in scadenza
    final certificatoInScadenza = user.certificatoScadenza != null && 
        CertificatoHelper.isCertificatoInScadenza(user.certificatoScadenza);
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          width: double.infinity,
          child: const Text('Il mio abbonamento', textAlign: TextAlign.left, style: TextStyle(color: onPrimaryColor, fontSize: 20),),
        ),
        Column(
          children: [
            CustomCard(
              backgroundColor: onSurfaceColor,
              title: getTipologiaIscrizioneTitle(user.tipologiaIscrizione!, isExpired), 
              description: getTipologiaIscrizioneDescription(user),
            ),
            if (certificatoInScadenza) _buildCertificatoInfo(),
          ],
        ),
        const SizedBox(height: 30,),
      ],
    );
  }

  Widget _buildCertificatoInfo() {
    final giorniRimanenti = CertificatoHelper.getGiorniRimanenti(user.certificatoScadenza);
    final dataScadenza = CertificatoHelper.formatDataScadenza(user.certificatoScadenza);
    
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: giorniRimanenti <= 3 ? Colors.red.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: giorniRimanenti <= 3 ? Colors.red.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.medical_services,
            color: giorniRimanenti <= 3 ? Colors.red.shade700 : Colors.orange.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Certificato in scadenza: $dataScadenza (${giorniRimanenti} giorni)',
              style: TextStyle(
                color: giorniRimanenti <= 3 ? Colors.red.shade700 : Colors.orange.shade700,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificatiInScadenzaCard() {
    if (user.role != 'Admin') {
      return const SizedBox.shrink();
    }

    if (isLoadingCertificati) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Caricamento certificati in scadenza...'),
          ],
        ),
      );
    }
    
    if (utentiConCertificatoInScadenza.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                'Certificati in Scadenza (${utentiConCertificatoInScadenza.length})',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...utentiConCertificatoInScadenza.map((utente) {
            final giorniRimanenti = CertificatoHelper.getGiorniRimanenti(utente.certificatoScadenza);
            final dataScadenza = CertificatoHelper.formatDataScadenza(utente.certificatoScadenza);
            
            return InkWell(
              onTap: () async {
                final updatedUser = await Navigator.push<FitropeUser>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailPage(user: utente),
                  ),
                );
                
                // Se l'utente è stato aggiornato, ricarica i certificati
                if (updatedUser != null) {
                  _loadUtentiConCertificatoInScadenza();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.red.shade100,
                      radius: 20,
                      child: Text(
                        '${utente.name.isNotEmpty ? utente.name[0] : ''}${utente.lastName.isNotEmpty ? utente.lastName[0] : ''}',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${utente.name} ${utente.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (giorniRimanenti >= 0) Text(
                            'Scadenza: $dataScadenza',
                            style: TextStyle(
                              color: Colors.red.shade600,
                              fontSize: 14,
                            ),
                          ) else Text('Scaduto il $dataScadenza', style: TextStyle(color: Colors.red.shade600, fontSize: 14,),),
                          
                          if (giorniRimanenti >= 0)
                            Text(
                              'Giorni rimanenti: $giorniRimanenti',
                              style: TextStyle(
                                color: giorniRimanenti <= 3 ? Colors.red : Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.red.shade400,
                      size: 16,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildAbbonamentiInScadenzaCard() {
    if (user.role != 'Admin') {
      return const SizedBox.shrink();
    }

    if (isLoadingAbbonamenti) {
      return Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Caricamento abbonamenti in scadenza...'),
          ],
        ),
      );
    }
    
    if (utentiConAbbonamentoInScadenza.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, color: Colors.orange.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                'Abbonamenti in Scadenza (${utentiConAbbonamentoInScadenza.length})',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...utentiConAbbonamentoInScadenza.map((utente) {
            final giorniRimanenti = AbbonamentoHelper.getGiorniRimanenti(utente.fineIscrizione);
            final dataScadenza = AbbonamentoHelper.formatDataScadenza(utente.fineIscrizione);
            
            return InkWell(
              onTap: () async {
                final updatedUser = await Navigator.push<FitropeUser>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailPage(user: utente),
                  ),
                );
                
                // Se l'utente è stato aggiornato, ricarica gli abbonamenti
                if (updatedUser != null) {
                  _loadUtentiConAbbonamentoInScadenza();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange.shade100,
                      radius: 20,
                      child: Text(
                        '${utente.name.isNotEmpty ? utente.name[0] : ''}${utente.lastName.isNotEmpty ? utente.lastName[0] : ''}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${utente.name} ${utente.lastName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Scadenza: $dataScadenza',
                            style: TextStyle(
                              color: Colors.orange.shade600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Abbonamento: ${getTipologiaIscrizioneLabel(utente.tipologiaIscrizione)}',
                            style: TextStyle(
                              color: Colors.orange.shade600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Giorni rimanenti: $giorniRimanenti',
                            style: TextStyle(
                              color: giorniRimanenti <= 3 ? Colors.red : Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.orange.shade400,
                      size: 16,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  List<Widget> renderCourses() {
    if(user.courses.isEmpty) {
      return [
        const SizedBox(height: 10,),
        const Text('Nessun corso disponibile',)
      ];
    }

    List<Widget> render = [];

    for(int n=0; n<user.courses.length; n++) {
      // Usa course.uid invece di course.id per la sincronizzazione
      Course? course = allCourses.where((Course course) => course.uid == user.courses[n]).firstOrNull;

      if(course != null && getCourseState(course, user) != CourseState.EXPIRED) {
        render.add(
          CoursePreviewCard(
            course: course,
            currentUser: user,
            trainers: trainers,
            showDate: true,
            onSubscribe: () => onSubscribe(course),
            onUnsubscribe: () => onUnsubscribe(course),
            onRefresh: () => refreshCourses(),
          ),
        );
      }
    }

    if(render.isEmpty) {
      return [
        const SizedBox(height: 10,),
        const Text('Nessun corso disponibile', style: TextStyle(color: onPrimaryColor),)
      ];
    }

    return render;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: pagePadding, right: pagePadding, bottom: pagePadding, top: pagePadding + MediaQuery.of(context).viewPadding.top),
      child: Column(
        children: [
          // HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Image(image: AssetImage('assets/new_logo_only.png'), width: 30,),
              const Text('Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: onPrimaryColor),),
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
              )
            ],
          ),

          // CERTIFICATI IN SCADENZA (solo per Admin)
          _buildCertificatiInScadenzaCard(),

          // ABBONAMENTI IN SCADENZA (solo per Admin)
          _buildAbbonamentiInScadenzaCard(),

          // ABBONAMENTO
          renderSubscriptionCard(),

          // CORSI
          Column(
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                width: double.infinity,
                child: const Text('I miei corsi', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
              ),
              ...renderCourses()
            ],
          ),
        ],
      ),
    );
  }
}