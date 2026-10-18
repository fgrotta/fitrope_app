import 'package:flutter/material.dart';
import 'package:fitrope_app/style.dart';

/// Card di selezione dell'immagine del corso, condivisa dalle pagine di
/// creazione/modifica corso (CourseManagementPage, RecurringCoursePage).
/// Toccare una miniatura la seleziona; la lente la apre ingrandita.
class CourseImageSelectorCard extends StatelessWidget {
  final List<String> images;
  final String? selected;
  final ValueChanged<String> onSelected;

  const CourseImageSelectorCard({
    super.key,
    required this.images,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: surfaceVariantColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Immagine del Corso',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Seleziona un\'immagine per questo corso. Tocca la lente per ingrandirla.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) =>
                    _buildThumbnail(context, images[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, String imagePath) {
    final isSelected = selected == imagePath;
    return Stack(
      children: [
        GestureDetector(
          key: ValueKey('course-image-thumb:$imagePath'),
          onTap: () => onSelected(imagePath),
          child: Container(
            width: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? primaryColor : Colors.transparent,
                width: 3,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: _image(imagePath, cacheWidth: 300),
            ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              key: ValueKey('course-image-zoom:$imagePath'),
              tooltip: 'Ingrandisci',
              icon: const Icon(Icons.zoom_in, color: Colors.white, size: 18),
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              onPressed: () => _showPreview(context, imagePath),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPreview(BuildContext context, String imagePath) {
    final isSelected = selected == imagePath;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          // Gli asset sono 800 px: oltre si sgranerebbero.
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 5 / 3,
                child: _image(
                  imagePath,
                  key: ValueKey('course-image-preview:$imagePath'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Chiudi'),
                    ),
                    const SizedBox(width: 8),
                    if (isSelected)
                      const FilledButton(
                        onPressed: null,
                        child: Text('Immagine selezionata'),
                      )
                    else
                      FilledButton(
                        onPressed: () {
                          onSelected(imagePath);
                          Navigator.of(dialogContext).pop();
                        },
                        child: const Text('Usa questa immagine'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image(String imagePath, {Key? key, int? cacheWidth}) {
    return Image.asset(
      imagePath,
      key: key,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stackTrace) => Container(
        color: primaryLightColor.withValues(alpha: 0.3),
        child: const Center(
          child: Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      ),
    );
  }
}
