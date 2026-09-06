import 'package:flutter/material.dart';

import 'brand.dart';

/// ARCHIVED. Nothing in the app opens this screen.
///
/// It is kept whole, and compiling, so that changing the mark's motion is a
/// one-line decision rather than a rebuild: add a row back to look_screen.dart
/// that pushes `MarkMotionScreen`, and the three variants and the duration
/// slider are there again.
///
/// The three motions, side by side. Unfurl is the one in the app; the other
/// two are kept here rather than deleted.
///
/// Keeping them is deliberate. Bloom answers a question that has not been
/// asked yet — what plays on every cold start, where 950ms of theatre would
/// become a tax — and Sweep is the most distinctive of the three and the
/// closest to what a *prahar* actually is. Deleting them would mean
/// rediscovering both from a filmstrip.
///
/// This screen is also where a timing is judged: a still cannot show the
/// overshoot as the sun and hand pass their final positions and settle, and
/// it cannot show when a duration starts to feel long.
class MarkMotionScreen extends StatefulWidget {
  const MarkMotionScreen({super.key});

  @override
  State<MarkMotionScreen> createState() => _MarkMotionScreenState();
}

class _MarkMotionScreenState extends State<MarkMotionScreen> {
  // Bumped to replay. Every card watches the same counter so "Play all"
  // starts the three together and they can be compared in one pass.
  int _take = 0;
  int _ms = 950;

  static const _variants = <(MarkMotion, String, String)>[
    (
      MarkMotion.unfurl,
      'Unfurl · in use',
      'Sun first, then the ring written on clockwise, then the hand. The mark '
          'being assembled. This is what the first-run screen plays.',
    ),
    (
      MarkMotion.bloom,
      'Bloom · archived',
      'Everything overlapping, landing together. Shorter, and the one that '
          'would survive playing on every launch.',
    ),
    (
      MarkMotion.sweep,
      'Sweep · archived',
      'The hand leads from the first frame and the ticks trail behind it, as '
          'though the hand were drawing them.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark motion'),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _take++),
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: const Text('Play all'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(
            'Tap any mark to replay just that one. The slider changes how long '
            'all three take.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('${_ms}ms', style: theme.textTheme.labelMedium),
              Expanded(
                child: Slider(
                  value: _ms.toDouble(),
                  min: 400,
                  max: 1800,
                  divisions: 14,
                  onChanged: (v) => setState(() => _ms = v.round()),
                  onChangeEnd: (_) => setState(() => _take++),
                ),
              ),
            ],
          ),
          for (final (motion, name, blurb) in _variants)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        // A tap replays this one alone, which is how a single
                        // curve gets judged.
                        onTap: () => setState(() => _take++),
                        child: AnimatedPraharMark(
                          size: 96,
                          motion: motion,
                          duration: Duration(milliseconds: _ms),
                          replayKey: '$_take-$motion',
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              blurb,
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
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'At 84px this is the size the first-run screen draws it. In the '
            'app bar it is 24px, where the ticks are close to a pixel wide and '
            'most of this motion would be lost.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
