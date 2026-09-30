import 'package:fitrope_app/pages/protected/guide/guide_catalog.dart';
import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Larghezza massima del testo: oltre, le righe diventano troppo lunghe da
/// leggere e gli screenshot (1280 px) verrebbero ingranditi oltre l'originale.
const double guideMaxContentWidth = 820;

/// Una guida della Guida Admin, renderizzata dal suo Markdown.
///
/// Nel Markdown:
/// - `![didascalia](img/<id>/NN-passo.png)` → immagine da
///   `assets/guida/img/…`, con zoom al tap (anche i `.webp` animati);
/// - `[testo](guida:<id>)` → link a un'altra guida del catalogo.
class GuidePage extends StatefulWidget {
  final GuideEntry entry;
  final List<GuideEntry> catalog;

  const GuidePage({
    super.key,
    required this.entry,
    this.catalog = guideCatalog,
  });

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  Future<String>? _markdown;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _markdown ??= DefaultAssetBundle.of(context).loadString(widget.entry.asset);
  }

  void _onTapLink(String text, String? href, String title) {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (uri.scheme == 'guida') {
      final target = guideById(uri.path, widget.catalog);
      if (target == null) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GuidePage(entry: target, catalog: widget.catalog),
      ));
      return;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: Text(widget.entry.title),
      ),
      body: FutureBuilder<String>(
        future: _markdown,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(pagePadding),
                child: Text('Impossibile caricare la guida'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: guideMaxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      pagePadding, 8, pagePadding, pagePadding * 3),
                  child: SelectionArea(
                    child: MarkdownBody(
                      data: snapshot.data!,
                      styleSheet: _styleSheet(context),
                      onTapLink: _onTapLink,
                      imageBuilder: (uri, title, alt) =>
                          GuideImage(path: uri.path, caption: alt),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final theme = Theme.of(context);
    const body = TextStyle(fontSize: 16, height: 1.5, color: onSurfaceColor);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      listBullet: body,
      h1: const TextStyle(
          fontSize: 28, fontWeight: FontWeight.bold, color: onPrimaryColor),
      h2: const TextStyle(
          fontSize: 21, fontWeight: FontWeight.w600, color: onPrimaryColor),
      h3: const TextStyle(
          fontSize: 17, fontWeight: FontWeight.w600, color: onPrimaryColor),
      h2Padding: const EdgeInsets.only(top: 20),
      h3Padding: const EdgeInsets.only(top: 12),
      blockSpacing: 12,
      a: const TextStyle(
          color: primaryColor, decoration: TextDecoration.underline),
      code: const TextStyle(
        fontSize: 14,
        color: onPrimaryColor,
        backgroundColor: surfaceVariantColor,
        fontFamily: 'monospace',
      ),
      // I blockquote sono i riquadri "Attenzione" delle guide.
      blockquote: body,
      blockquotePadding: const EdgeInsets.all(12),
      blockquoteDecoration: BoxDecoration(
        color: warningColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: warningColor, width: 4)),
      ),
      tableBody: body,
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBorder: TableBorder.all(color: outlineColor),
      tableCellsPadding: const EdgeInsets.all(8),
    );
  }
}

/// Immagine di una guida: bordo sottile, didascalia e zoom a schermo intero.
class GuideImage extends StatelessWidget {
  /// Percorso relativo ad `assets/guida/`, es. `img/corsi/01-calendario.png`.
  final String path;
  final String? caption;

  const GuideImage({super.key, required this.path, this.caption});

  String get assetName => 'assets/guida/$path';

  void _openZoom(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image.asset(
                    assetName,
                    errorBuilder: (context, error, stack) => const Text(
                      'Immagine non disponibile',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: 'Chiudi',
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: GestureDetector(
              onTap: () => _openZoom(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: outlineColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    assetName,
                    semanticLabel: caption,
                    errorBuilder: (context, error, stack) => const SizedBox(
                      height: 120,
                      child: Center(child: Text('Immagine non disponibile')),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null && caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                caption!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: onSurfaceVariantColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
