import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/di/view_models.dart';
import '../../config/router/app_router.dart';
import '../../config/theme/app_metrics.dart';
import '../../config/theme/app_palette.dart';
import '../../data/models/api_keys.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/byte_size.dart';
import '../../data/models/model_descriptor.dart';
import '../../data/models/projector_descriptor.dart';
import '../../data/repositories/model_library_repository.dart';
import '../widgets/about_card.dart';
import '../widgets/api_key_card.dart';
import '../widgets/appearance_selector.dart';
import '../widgets/installed_model_card.dart';
import '../widgets/runtime_defaults_card.dart';
import '../widgets/section_heading.dart';
import '../widgets/settings_header.dart';
import '../widgets/storage_card.dart';

/// Keys, models, appearance, runtime defaults, storage and about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;
    final library = ref.watch(modelLibraryViewModelProvider).value;
    final settings = ref.watch(appSettingsViewModelProvider).value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: <Widget>[
            _Block(top: metrics.gapLg, child: const SettingsHeader()),
            _Block(
              top: metrics.gapLg,
              child: const SectionHeading(title: 'API keys'),
            ),
            for (final kind in ApiKeyKind.values)
              _Block(
                top: metrics.gapMd,
                child: ApiKeyCard(kind: kind),
              ),
            _Block(
              top: metrics.gapXl,
              child: SectionHeading(
                title: _modelsTitle(library),
                actionLabel: 'Browse models',
                onAction: () => context.push(Routes.catalog),
              ),
            ),
            _ModelList(library: library ?? ModelLibrary.empty),
            _Block(
              top: metrics.gapXl,
              child: const SectionHeading(title: 'Appearance'),
            ),
            _Block(
              top: metrics.gapMd,
              child: AppearanceSelector(
                value: settings?.themeMode ?? ThemeMode.system,
                onChanged: ref
                    .read(appSettingsViewModelProvider.notifier)
                    .setThemeMode,
              ),
            ),
            _Block(
              top: metrics.gapXl,
              child: const SectionHeading(title: 'Runtime defaults'),
            ),
            _Block(
              top: metrics.gapMd,
              child: RuntimeDefaultsCard(
                settings: settings ?? const AppSettings(),
              ),
            ),
            _Block(
              top: metrics.gapXl,
              child: const SectionHeading(title: 'Storage'),
            ),
            _Block(top: metrics.gapMd, child: const StorageCard()),
            _Block(
              top: metrics.gapXl,
              child: const SectionHeading(title: 'About'),
            ),
            _Block(
              top: metrics.gapMd,
              bottom: metrics.gapXl,
              child: const AboutCard(),
            ),
          ],
        ),
      ),
    );
  }

  /// `Models · 8.06 GB` — the heading doubles as the only place the user can
  /// see what the library costs in total.
  static String _modelsTitle(ModelLibrary? library) {
    if (library == null || library.isEmpty) return 'Models';
    return 'Models · ${formatBytes(library.totalBytes)}';
  }
}

/// One page-padded row in the scroll view.
class _Block extends StatelessWidget {
  const _Block({required this.child, this.top = 0, this.bottom = 0});

  final Widget child;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        top,
        metrics.pagePadding,
        bottom,
      ),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}

class _ModelList extends ConsumerWidget {
  const _ModelList({required this.library});

  final ModelLibrary library;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = context.metrics;

    if (library.isEmpty) {
      return _Block(top: metrics.gapMd, child: const _NoModels());
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        metrics.pagePadding,
        metrics.gapMd,
        metrics.pagePadding,
        0,
      ),
      sliver: SliverList.separated(
        itemCount: library.models.length,
        separatorBuilder: (_, _) => SizedBox(height: metrics.gapMd),
        itemBuilder: (context, index) {
          final model = library.models[index];
          return InstalledModelCard(
            key: ValueKey<String>(model.id),
            model: model,
            isActive: model.id == library.activeId,
            hasVision: library.hasVision(model),
            onSelect: () => ref
                .read(modelLibraryViewModelProvider.notifier)
                .setActive(model.id),
            onRemove: () => _confirmRemove(context, ref, library, model),
          );
        },
      ),
    );
  }

  /// Deleting weights means re-downloading gigabytes, so it asks first — the
  /// same dialog the Chats list uses before deleting a session. A repository
  /// with a projector gets a third action, because the projector is shared
  /// and the user is the only one who knows whether they are done with it.
  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ModelLibrary library,
    ModelDescriptor model,
  ) async {
    final projector = library.projectorFor(model.repoId);
    final choice = await showDialog<_RemoveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${model.name}?'),
        content: Text(_removeBlurb(library, model, projector)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(_RemoveChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_RemoveChoice.modelOnly),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: Text(projector == null ? 'Remove' : 'Delete model'),
          ),
          if (projector != null)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_RemoveChoice.withProjector),
              style: TextButton.styleFrom(
                foregroundColor: context.palette.danger,
              ),
              child: const Text('Delete model and projector'),
            ),
        ],
      ),
    );

    if (choice == null || choice == _RemoveChoice.cancel) return;
    await ref
        .read(modelLibraryViewModelProvider.notifier)
        .remove(model.id, alsoProjector: choice == _RemoveChoice.withProjector);
  }

  /// What the dialog says. With a shared projector it names the models that
  /// would lose their sight, since that cost is not obvious from the row.
  static String _removeBlurb(
    ModelLibrary library,
    ModelDescriptor model,
    ProjectorDescriptor? projector,
  ) {
    final base =
        'This deletes ${model.sizeLabel} from this device. You can download '
        'it again from Hugging Face.';
    if (projector == null) return base;

    final sharers = library.modelsOf(model.repoId, exceptId: model.id);
    if (sharers.isEmpty) {
      return '$base\n\nThis repository also has a ${projector.sizeLabel} '
          'vision projector, which nothing else is using.';
    }
    final names = sharers.map((m) => m.name).join(', ');
    return '$base\n\nIts ${projector.sizeLabel} vision projector is shared '
        'with $names — deleting it leaves them unable to read images.';
  }
}

/// What the remove dialog came back with.
enum _RemoveChoice { cancel, modelOnly, withProjector }

class _NoModels extends StatelessWidget {
  const _NoModels();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final metrics = context.metrics;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: metrics.gapLg),
      child: Text(
        'No models yet. Add one to start chatting.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: palette.muted),
      ),
    );
  }
}
