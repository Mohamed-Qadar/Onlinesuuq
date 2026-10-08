import 'package:flutter/material.dart';

const developerName = 'Eng. Mohamed Ibrahim Abdi';
const developerSpecialty =
    'Computer Engineer\nSpecialty: Natural Language Processing and Computer Vision';
const developerContact = 'mohamedqadar280@gmail.com';

/// Build-time attribution, independent of user settings and inventory backups.
class DeveloperCredit extends StatelessWidget {
  const DeveloperCredit({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        const Text(developerName, style: TextStyle(fontSize: 12)),
        const SelectableText(developerContact, style: TextStyle(fontSize: 12)),
        IconButton(
          tooltip: Localizations.localeOf(context).languageCode == 'so'
              ? 'Ku saabsan horumariyaha'
              : 'About the developer',
          icon: const Icon(Icons.info_outline, size: 18),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              scrollable: true,
              title: const Text(developerName),
              content: const SelectableText(
                '$developerSpecialty\n\nContact me\n$developerContact',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    Localizations.localeOf(context).languageCode == 'so'
                        ? 'Xir'
                        : 'Close',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
