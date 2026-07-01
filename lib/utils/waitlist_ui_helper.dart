import 'package:fitrope_app/api/courses/joinWaitlist.dart';
import 'package:fitrope_app/api/courses/leaveWaitlist.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';

class WaitlistUiHelper {
  /// Mostra il dialog di conferma e iscrive l'utente alla lista d'attesa.
  static void showJoinWaitlistDialog({
    required BuildContext context,
    required Course course,
    required String userId,
    required VoidCallback onRefresh,
    required bool Function() isMounted,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: backgroundColor,
        title: const Text('Lista d\'attesa'),
        content: Text(
          'Vuoi iscriverti alla lista d\'attesa per "${course.name}"?\n\nRiceverai una email se si libera un posto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                const Text('Annulla', style: TextStyle(color: onPrimaryColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              joinWaitlist(course.uid, userId).then((_) {
                onRefresh();
                if (isMounted()) {
                  SnackBarUtils.showSuccessSnackBar(
                      context, 'Iscritto alla lista d\'attesa');
                }
              }).catchError((e) {
                if (isMounted()) {
                  SnackBarUtils.showErrorSnackBar(
                      context, 'Errore: ${e.toString()}');
                }
              });
            },
            child:
                const Text('Conferma', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  /// Rimuove l'utente dalla lista d'attesa.
  static void handleLeaveWaitlist({
    required BuildContext context,
    required Course course,
    required String userId,
    required VoidCallback onRefresh,
    required bool Function() isMounted,
  }) {
    leaveWaitlist(course.uid, userId).then((_) {
      onRefresh();
      if (isMounted()) {
        SnackBarUtils.showSuccessSnackBar(
            context, 'Rimosso dalla lista d\'attesa');
      }
    }).catchError((e) {
      if (isMounted()) {
        SnackBarUtils.showErrorSnackBar(context, 'Errore: ${e.toString()}');
      }
    });
  }
}
