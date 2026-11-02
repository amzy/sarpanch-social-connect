import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceControllerProvider);
    final controller = ref.read(appearanceControllerProvider.notifier);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance & themes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Color theme', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Choose an accent palette. Your Panchayat logo, official seal and poster identity remain unchanged.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ...AppThemeId.values.map((themeId) {
            final palette = brandPalettes[themeId]!;
            final selected = appearance.themeId == themeId;
            return Card(
              child: RadioListTile<AppThemeId>(
                value: themeId,
                groupValue: appearance.themeId,
                onChanged: (value) {
                  if (value != null) controller.selectTheme(value);
                },
                title: Text(themeId.label),
                subtitle: Text(themeId.description),
                secondary: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: palette.seed,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
            );
          }),
          const SizedBox(height: 24),
          Text('Appearance mode', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Use light or dark appearance, or follow your device setting.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            value: appearance.themeMode,
            decoration: const InputDecoration(labelText: 'Display mode'),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('Follow system')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
            onChanged: (value) {
              if (value != null) controller.selectMode(value);
            },
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.translate),
              title: const Text('Post content language'),
              subtitle: const Text(
                'Configured separately in your profile and post composer. The app interface remains English.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
