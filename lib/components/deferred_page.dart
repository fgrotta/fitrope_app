import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

/// Carica una libreria differita (`deferred as`) mostrando uno spinner finché il
/// chunk `*.part.js` non è pronto, poi costruisce la pagina.
class DeferredPage extends StatefulWidget {
  /// Funzione che avvia (o restituisce) il caricamento della libreria differita,
  /// tipicamente `prefix.loadLibrary`. Deve essere idempotente.
  final Future<void> Function() loader;

  /// Costruisce la pagina una volta che la libreria è caricata.
  final WidgetBuilder builder;

  /// Se la libreria è GIÀ caricata (es. tab di una bottom bar rimontata dopo un
  /// prewarm), costruisce subito la pagina saltando il `FutureBuilder`: evita il
  /// frame di spinner a pagina intera ad ogni rientro nella tab.
  final bool alreadyLoaded;

  const DeferredPage({
    super.key,
    required this.loader,
    required this.builder,
    this.alreadyLoaded = false,
  });

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  // Non-final: in caso di errore di rete sul chunk, "Riprova" ricrea il future.
  late Future<void> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    if (widget.alreadyLoaded) return widget.builder(context);
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: primaryColor)),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Errore nel caricamento della pagina.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => setState(() => _future = widget.loader()),
                    child: const Text('Riprova'),
                  ),
                ],
              ),
            ),
          );
        }
        return widget.builder(context);
      },
    );
  }
}
