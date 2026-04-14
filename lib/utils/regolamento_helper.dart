import 'package:fitrope_app/api/authentication/acceptRegolamento.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Helper per mostrare il dialog di accettazione del regolamento della palestra
class RegolamentoHelper {
  static const String regolamentoUrl =
      'https://www.fithousemonza.it/regolamento-della-palestra/';

  /// Controlla se l'utente ha già accettato il regolamento.
  /// Se sì, ritorna true immediatamente.
  /// Se no, mostra il dialog e salva l'accettazione su Firestore.
  static Future<bool> checkAndAcceptRegolamento(
    BuildContext context,
    FitropeUser user,
  ) async {
    // Già accettato: nessun dialog
    if (user.regolamentoAccettatoIl != null) {
      return true;
    }

    // Mostra dialog di accettazione
    final accepted = await _showRegolamentoDialog(context);
    if (!accepted) return false;

    // Salva su Firestore
    try {
      await acceptRegolamento(user.uid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Errore durante il salvataggio dell\'accettazione del regolamento'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    return true;
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
