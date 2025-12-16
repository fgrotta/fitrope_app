import 'package:flutter/material.dart';
import 'package:fitrope_app/types/course.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:fitrope_app/utils/course_unsubscribe_helper.dart';

/// Pulsante di disiscrizione intelligente che gestisce automaticamente i controlli temporali
/// (4 ore per abbonamenti temporali, 8 ore per pacchetti entrate)
class CourseUnsubscribeButton extends StatefulWidget {
  final Course course;
  final FitropeUser user;
  final VoidCallback? onUnsubscribed;
  final VoidCallback? onError;
  
  const CourseUnsubscribeButton({
    super.key,
    required this.course,
    required this.user,
    this.onUnsubscribed,
    this.onError,
  });

  @override
  State<CourseUnsubscribeButton> createState() => _CourseUnsubscribeButtonState();
}

class _CourseUnsubscribeButtonState extends State<CourseUnsubscribeButton> {
  bool _isLoading = false;
  late Map<String, dynamic> _unsubscribeInfo;

  @override
  void initState() {
    super.initState();
    _unsubscribeInfo = CourseUnsubscribeHelper.canUnsubscribe(widget.course, widget.user);
  }

  @override
  Widget build(BuildContext context) {
    if (!_unsubscribeInfo['canUnsubscribe']) {
      return const SizedBox.shrink(); // Non mostrare il pulsante se non può disiscriversi
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Messaggio informativo
        if (_unsubscribeInfo['message'] != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getMessageColor(),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  _getMessageIcon(),
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _unsubscribeInfo['message'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        
        // Pulsante di disiscrizione
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleUnsubscribe,
            style: ElevatedButton.styleFrom(
              backgroundColor: _getButtonColor(),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(_getButtonText()),
          ),
        ),
      ],
    );
  }

  Color _getMessageColor() {
    if (_unsubscribeInfo['requiresConfirmation']) {
      return Colors.orange;
    } else if (_unsubscribeInfo['isPacchettoEntrate']) {
      return Colors.green;
    } else {
      return Colors.blue;
    }
  }

  IconData _getMessageIcon() {
    if (_unsubscribeInfo['requiresConfirmation']) {
      return Icons.warning;
    } else if (_unsubscribeInfo['isPacchettoEntrate']) {
      return Icons.check_circle;
    } else {
      return Icons.info;
    }
  }

  Color _getButtonColor() {
    if (_unsubscribeInfo['requiresConfirmation']) {
      return Colors.orange; // Colore di attenzione per richiedere conferma
    } else {
      return Colors.red; // Colore normale per disiscrizione
    }
  }

  String _getButtonText() {
    if (_unsubscribeInfo['requiresConfirmation']) {
      return 'Disiscriviti (Perdi Credito)';
    } else {
      return 'Disiscriviti';
    }
  }

  Future<void> _handleUnsubscribe() async {
    setState(() {
      _isLoading = true;
    });

    try {
      bool success = await CourseUnsubscribeHelper.handleUnsubscribe(
        widget.course,
        widget.user,
        context,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disiscrizione completata con successo'),
              backgroundColor: Colors.green,
            ),
          );
        }
        widget.onUnsubscribed?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante la disiscrizione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      widget.onError?.call();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}

/// Pulsante di disiscrizione semplice per uso rapido
class SimpleUnsubscribeButton extends StatelessWidget {
  final Course course;
  final FitropeUser user;
  final VoidCallback? onUnsubscribed;
  
  const SimpleUnsubscribeButton({
    super.key,
    required this.course,
    required this.user,
    this.onUnsubscribed,
  });

  @override
  Widget build(BuildContext context) {
    final unsubscribeInfo = CourseUnsubscribeHelper.canUnsubscribe(course, user);
    
    return ElevatedButton(
      onPressed: () => _handleSimpleUnsubscribe(context),
      style: ElevatedButton.styleFrom(
        backgroundColor: unsubscribeInfo['requiresConfirmation'] ? Colors.orange : Colors.red,
        foregroundColor: Colors.white,
      ),
      child: Text(unsubscribeInfo['requiresConfirmation'] ? 'Disiscriviti (Perdi Credito)' : 'Disiscriviti'),
    );
  }

  Future<void> _handleSimpleUnsubscribe(BuildContext context) async {
    try {
      bool success = await CourseUnsubscribeHelper.handleUnsubscribe(
        course,
        user,
        context,
      );

      if (success && onUnsubscribed != null) {
        onUnsubscribed!();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
