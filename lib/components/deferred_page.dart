import 'package:flutter/material.dart';
import 'package:fitrope_app/components/loader.dart';

/// Wrapper per le route caricate in modo differito (deferred loading).
///
/// Le pagine dell'area protetta sono importate con `deferred as` nel router:
/// non finiscono nel bundle iniziale e vengono scaricate alla prima
/// navigazione (o pre-caricate durante lo splash). [DeferredPage] attende il
/// `loadLibrary()` del chunk mostrando un [Loader], poi costruisce la pagina.
///
/// Il `Future` di [load] è catturato una sola volta (in [initState]): se il
/// chunk è già stato caricato — es. pre-warmed dallo SplashScreen —
/// `loadLibrary()` ritorna immediatamente e non c'è alcun loader visibile.
class DeferredPage extends StatefulWidget {
  /// Tipicamente il `loadLibrary` del prefisso deferred (es. `protected.loadLibrary`).
  final Future<void> Function() load;

  /// Costruisce la pagina effettiva DOPO che il chunk è stato caricato.
  final WidgetBuilder builder;

  const DeferredPage({super.key, required this.load, required this.builder});

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  late final Future<void> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Impossibile caricare la pagina. Controlla la connessione e ricarica.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Loader());
        }
        return widget.builder(context);
      },
    );
  }
}

/// Come [DeferredPage], ma per una sezione dentro una pagina già montata: al
/// posto dello Scaffold con il velo del [Loader] mostra un piccolo spinner in
/// linea, e in caso di errore un messaggio che non copre il resto della
/// pagina.
///
/// Serve per il codice che solo alcuni ruoli usano (es. le sezioni admin della
/// Home): con la build dart2js finisce in un part separato che gli altri non
/// scaricano.
class DeferredSection extends StatefulWidget {
  /// Tipicamente il `loadLibrary` del prefisso deferred.
  final Future<void> Function() load;

  /// Costruisce la sezione DOPO che il chunk è stato caricato.
  final WidgetBuilder builder;

  const DeferredSection({super.key, required this.load, required this.builder});

  @override
  State<DeferredSection> createState() => _DeferredSectionState();
}

class _DeferredSectionState extends State<DeferredSection> {
  late final Future<void> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Impossibile caricare questa sezione. Ricarica la pagina.',
              textAlign: TextAlign.center,
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return widget.builder(context);
      },
    );
  }
}
