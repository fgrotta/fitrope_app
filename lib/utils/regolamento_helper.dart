import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fitrope_app/api/authentication/accept_regolamento.dart';
import 'package:fitrope_app/api/get_user_data.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/types/fitrope_user.dart';
import 'package:fitrope_app/utils/refresh_current_user.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper per mostrare il dialog di accettazione del regolamento della palestra
///
/// Il gate vero è server-side (`subscribeToCourse` / `joinWaitlist` rifiutano
/// il socio senza marca): questo dialog serve a raccoglierla prima della
/// callable, così l'utente non vede un errore.
class RegolamentoHelper {
  static const String regolamentoUrl =
      'https://www.fithousemonza.it/regolamento-della-palestra/';

  /// Controlla se l'utente ha già accettato il regolamento.
  /// Se sì, ritorna true immediatamente.
  /// Se no, mostra il dialog e salva l'accettazione su Firestore.
  static Future<bool> checkAndAcceptRegolamento(
    BuildContext context,
    FitropeUser user, {
    FirebaseFirestore? firestore,
  }) async {
    // Già accettato: nessun dialog
    if (_hasAccepted(user)) {
      return true;
    }

    // Mostra dialog di accettazione
    final accepted = await _showRegolamentoDialog(context);
    if (!accepted) return false;

    // Salva su Firestore
    try {
      await acceptRegolamento(user.uid, firestore: firestore);
    } catch (e) {
      // La marca è write-once nelle rules: se il documento la ha già (stato
      // locale stantio) la scrittura è rifiutata, ma l'accettazione vale.
      final refreshed = await _refreshStoreUser(user.uid, firestore);
      if (refreshed?.regolamentoAccettatoIl != null) return true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Errore durante il salvataggio dell\'accettazione del regolamento'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    // Lo store deve riflettere l'accettazione: se l'iscrizione che segue
    // fallisce (corso pieno, limiti), al tentativo successivo il dialog non
    // deve ricomparire.
    await _refreshStoreUser(user.uid, firestore);
    return true;
  }

  /// Le pagine tengono una copia locale dell'utente che non si aggiorna se la
  /// callable fallisce: vale anche la marca già presente nello store.
  static bool _hasAccepted(FitropeUser user) {
    if (user.regolamentoAccettatoIl != null) return true;
    final current = store.state.user;
    return current != null &&
        current.uid == user.uid &&
        current.regolamentoAccettatoIl != null;
  }

  /// Rilegge l'utente e lo installa nello store se è ancora l'utente corrente.
  /// Un errore di lettura non è fatale: la marca è già salvata.
  static Future<FitropeUser?> _refreshStoreUser(
    String uid,
    FirebaseFirestore? firestore,
  ) async {
    try {
      final userData = await getUserData(uid, firestore: firestore);
      if (userData == null) return null;
      final refreshed = FitropeUser.fromJson(userData);
      dispatchUserRefreshIfCurrent(refreshed);
      return refreshed;
    } catch (e) {
      debugPrint('Errore nel ricaricare l\'utente dopo il regolamento: $e');
      return null;
    }
  }

  /// Apre il link del regolamento nel browser.
  static Future<void> openRegolamento() async {
    final url = Uri.parse(regolamentoUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  /// Mostra il dialog di accettazione del regolamento.
  /// Restituisce true se l'utente accetta, false se annulla.
  static Future<bool> _showRegolamentoDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            bool accepted = false;
            String? errorMessage;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Regolamento della Palestra'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Per proseguire conferma di aver letto il regolamento della palestra:',
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => openRegolamento(),
                        child: const Text(
                          'Regolamento completo',
                          style: TextStyle(
                            color: Colors.blueAccent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            accepted = !accepted;
                            if (accepted) errorMessage = null;
                          });
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: accepted,
                              onChanged: (value) {
                                setState(() {
                                  accepted = value ?? false;
                                  if (accepted) errorMessage = null;
                                });
                              },
                            ),
                            const Expanded(
                              child: Text(
                                'Ho letto e accetto il regolamento della palestra',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 12.0, top: 4.0),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Annulla'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (!accepted) {
                          setState(() {
                            errorMessage =
                                'Devi accettare il regolamento per procedere';
                          });
                          return;
                        }
                        Navigator.of(context).pop(true);
                      },
                      child: const Text('Conferma'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;
  }
}
