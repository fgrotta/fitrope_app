import 'package:fitrope_app/api/courses/join_waitlist.dart';
import 'package:fitrope_app/api/courses/leave_waitlist.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';

class WaitlistUiHelper {
  /// Mostra il dialog di conferma e iscrive l'utente alla lista d'attesa.
  static Future<void> showJoinWaitlistDialog({
    required BuildContext context,
    required Course course,
    required String userId,
    required Future<void> Function() onRefresh,
    required bool Function() isMounted,
  }) async {
    final confirmed = await showDialog<bool>(
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
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                const Text('Conferma', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted || !isMounted()) return;

    try {
      await joinWaitlist(course.uid, userId);
      if (!context.mounted || !isMounted()) return;
      await onRefresh();
      if (context.mounted && isMounted()) {
        SnackBarUtils.showSuccessSnackBar(
            context, 'Iscritto alla lista d\'attesa');
      }
    } catch (e) {
      if (!context.mounted || !isMounted()) return;
      if (isMounted()) {
        SnackBarUtils.showErrorSnackBar(context, 'Errore: ${e.toString()}');
      }
    }
  }

  /// Rimuove l'utente dalla lista d'attesa.
  static Future<void> handleLeaveWaitlist({
    required BuildContext context,
    required Course course,
    required String userId,
    required Future<void> Function() onRefresh,
    required bool Function() isMounted,
  }) async {
    try {
      await leaveWaitlist(course.uid, userId);
      if (!context.mounted || !isMounted()) return;
      await onRefresh();
      if (context.mounted && isMounted()) {
        SnackBarUtils.showSuccessSnackBar(
            context, 'Rimosso dalla lista d\'attesa');
      }
    } catch (e) {
      if (!context.mounted || !isMounted()) return;
      if (isMounted()) {
        SnackBarUtils.showErrorSnackBar(context, 'Errore: ${e.toString()}');
      }
    }
  }
}
