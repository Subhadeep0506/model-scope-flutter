import 'package:checks/checks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/config/di/providers.dart';
import 'package:model_scope_flutter/main.dart';

import 'support/fakes.dart';

void main() {
  late FakeModelDownloader downloader;
  late ProviderContainer container;

  setUp(() {
    downloader = FakeModelDownloader();
    container = ProviderContainer(
      overrides: [modelDownloaderProvider.overrideWithValue(downloader)],
    );
    addTearDown(container.dispose);
    addTearDown(downloader.dispose);
  });

  group('afterFirstFrame', () {
    testWidgets('asks for the notification permission, once a frame is up', (
      tester,
    ) async {
      afterFirstFrame(container);
      check(downloader.notifyAsks).equals(0);

      await tester.pumpWidget(const SizedBox.shrink());
      check(downloader.notifyAsks).equals(1);

      await tester.pump();
      check(downloader.notifyAsks).equals(1);
    });
  });
}
