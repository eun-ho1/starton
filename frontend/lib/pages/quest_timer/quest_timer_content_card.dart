import 'package:flutter/material.dart';

class QuestTimerContentCard extends StatelessWidget {
  const QuestTimerContentCard({
    super.key,
    this.useLandscapeLayout = false,
    required this.header,
    required this.questSummary,
    required this.countdown,
    required this.actionButtons,
    required this.proofSection,
    required this.categoryTimes,
  });

  final bool useLandscapeLayout;
  final Widget header;
  final Widget questSummary;
  final Widget countdown;
  final Widget actionButtons;
  final Widget proofSection;
  final Widget categoryTimes;

  @override
  Widget build(BuildContext context) {
    if (useLandscapeLayout) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 4, bottom: 8),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    children: [
                      header,
                      const SizedBox(height: 18),
                      questSummary,
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: proofSection),
                          const SizedBox(width: 12),
                          Expanded(child: categoryTimes),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 26),
          Expanded(
            flex: 4,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    countdown,
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: actionButtons,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        const SizedBox(height: 18),
        questSummary,
        const SizedBox(height: 28),
        countdown,
        const SizedBox(height: 20),
        actionButtons,
        const SizedBox(height: 26),
        proofSection,
        const SizedBox(height: 24),
        categoryTimes,
      ],
    );
  }
}
