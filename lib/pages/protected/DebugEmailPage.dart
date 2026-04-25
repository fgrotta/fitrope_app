import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fitrope_app/services/notification_service.dart';

class DebugEmailPage extends StatefulWidget {
  const DebugEmailPage({super.key});

  @override
  State<DebugEmailPage> createState() => _DebugEmailPageState();
}

class _DebugEmailPageState extends State<DebugEmailPage> {
  final _recipientEmailCtrl = TextEditingController();
  final _courseNameCtrl = TextEditingController(text: 'Corso Test');
  final _courseDateCtrl = TextEditingController(text: 'Lunedì 28 Aprile 2025');
  final _courseTimeCtrl = TextEditingController(text: '10:00');
  final _spotsCtrl = TextEditingController(text: '2');

  String? _resolvedUid;
  String? _lookupError;
  bool _isLookingUp = false;
  bool _sendingWaitlist = false;
  bool _sendingReminder = false;

  @override
  void initState() {
    super.initState();
    final current = FirebaseAuth.instance.currentUser;
    _recipientEmailCtrl.text = current?.email ?? '';
    _resolvedUid = current?.uid;
  }

  @override
  void dispose() {
    _recipientEmailCtrl.dispose();
    _courseNameCtrl.dispose();
    _courseDateCtrl.dispose();
    _courseTimeCtrl.dispose();
    _spotsCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupUser() async {
    final email = _recipientEmailCtrl.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLookingUp = true;
      _lookupError = null;
      _resolvedUid = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (!mounted) return;

      if (snapshot.docs.isEmpty) {
        setState(() => _lookupError = 'Nessun utente trovato con questa email');
      } else {
        final uid = snapshot.docs.first.data()['uid'] as String?
            ?? snapshot.docs.first.id;
        setState(() => _resolvedUid = uid);
      }
    } catch (e) {
      if (mounted) setState(() => _lookupError = 'Errore: $e');
    } finally {
      if (mounted) setState(() => _isLookingUp = false);
    }
  }

  Future<void> _sendWaitlistEmail() async {
    if (_resolvedUid == null) return;
    setState(() => _sendingWaitlist = true);
    try {
      await sendTestWaitlistEmail(
        userId: _resolvedUid!,
        courseName: _courseNameCtrl.text,
        courseDate: _courseDateCtrl.text,
        courseTime: _courseTimeCtrl.text,
        spotsAvailable: int.tryParse(_spotsCtrl.text) ?? 1,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email waitlist inviata'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingWaitlist = false);
    }
  }

  Future<void> _sendReminderEmail() async {
    if (_resolvedUid == null) return;
    setState(() => _sendingReminder = true);
    try {
      await sendTestTrialReminderEmail(
        userId: _resolvedUid!,
        courseName: _courseNameCtrl.text,
        courseDate: _courseDateCtrl.text,
        courseTime: _courseTimeCtrl.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email promemoria inviata'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingReminder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'DebugEmailPage accessibile solo in debug mode');
    final canSend = _resolvedUid != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Email')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Destinatario ---
            const Text('Destinatario', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _recipientEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email destinatario',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _lookupUser(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLookingUp ? null : _lookupUser,
                    child: _isLookingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Cerca'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_lookupError != null)
              Text(
                _lookupError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
              )
            else if (_resolvedUid != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'UID: $_resolvedUid',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 28),

            // --- Dati corso ---
            const Text('Dati corso', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _courseNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome corso',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _courseDateCtrl,
              decoration: const InputDecoration(
                labelText: 'Data',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _courseTimeCtrl,
              decoration: const InputDecoration(
                labelText: 'Orario',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _spotsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Posti disponibili',
                border: OutlineInputBorder(),
                helperText: 'Usato solo per email waitlist',
              ),
            ),
            const SizedBox(height: 32),

            // --- Invio ---
            const Text('Tipo email', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canSend && !_sendingWaitlist ? _sendWaitlistEmail : null,
                icon: _sendingWaitlist
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.list_alt_outlined),
                label: const Text('Invia email waitlist'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canSend && !_sendingReminder ? _sendReminderEmail : null,
                icon: _sendingReminder
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.alarm_outlined),
                label: const Text('Invia promemoria prova'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
