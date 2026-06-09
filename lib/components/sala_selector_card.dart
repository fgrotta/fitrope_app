import 'package:flutter/material.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/utils/sale.dart';

/// Card di selezione della Sala, condivisa dalle pagine di creazione/modifica
/// corso (CourseManagementPage, RecurringCoursePage). `value == null` = nessuna sala.
class SalaSelectorCard extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const SalaSelectorCard({
    super.key,
    required this.value,
    required this.onChanged,
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
              'Sala',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              value: value,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              hint: const Text('Seleziona una sala'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Nessuna sala'),
                ),
                ...Sale.all.map((sala) => DropdownMenuItem<String?>(
                      value: sala,
                      child: Text(sala),
                    )),
              ],
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
