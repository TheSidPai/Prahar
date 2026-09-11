import 'package:flutter/material.dart';

import 'glass.dart';
import 'how_it_works.dart';

/// The short answer to "what am I meant to do here", one tap from Today.
///
/// Prompted by a first-time user who opened the app with no context and could
/// not tell what to do. The full guide already existed, as a small link under
/// the first-run button and a row in Settings, and was not found. A help button
/// in the same place on every visit to Today is findable, and four lines is
/// what someone in that moment will actually read. The full guide stays one tap
/// further for anyone who wants the reasons.
///
/// This is also where the first-run tour's replay will live, for the same
/// reason the autostart notice has a permanent Settings row: anything shown
/// once needs a way back.
///
/// The steps come from [howPraharWorksSteps], shared with the full guide.
Future<void> showHowItWorksSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SheetBackground(
      child: SafeArea(
        child: _HowItWorksSheet(
          onReadMore: () {
            // Close the sheet first, then open the guide from the screen
            // underneath, so Back from the guide lands on Today rather than
            // on a sheet the student already finished with.
            Navigator.pop(sheetContext);
            HowItWorks.open(context);
          },
        ),
      ),
    ),
  );
}

class _HowItWorksSheet extends StatelessWidget {
  const _HowItWorksSheet({required this.onReadMore});

  final VoidCallback onReadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Scrolls, so four steps at a large font on a small phone still reach the
    // link at the bottom instead of pushing it off the screen.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Named exactly as the full guide's page is, so the two read as the
          // same thing at two lengths.
          Text(
            'How Prahar works',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < howPraharWorksSteps.length; i++)
            _Step(
              number: i + 1,
              title: howPraharWorksSteps[i].title,
              short: howPraharWorksSteps[i].short,
            ),
          TextButton(
            key: const ValueKey('help-sheet-full-guide'),
            onPressed: onReadMore,
            child: const Text('Read the full guide'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.short});

  final int number;
  final String title;
  final String short;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A minimum rather than a fixed size, so the number's circle grows
          // with the student's font size instead of clipping the digit.
          Container(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.all(4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Expanded, so a large font wraps the text instead of overflowing
          // the row.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  short,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
