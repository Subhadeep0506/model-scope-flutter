import 'package:background_downloader/background_downloader.dart';
import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:model_scope_flutter/domain/services/model_downloader.dart';

void main() {
  group('shouldRequestNotifications', () {
    test('does not ask when the permission is already granted', () {
      // Android below 13 reports granted without ever having asked, and so
      // does any platform where the user has said yes.
      check(
        ModelDownloader.shouldRequestNotifications(PermissionStatus.granted),
      ).isFalse();
    });

    test('asks when the status is denied', () {
      // The case that matters: Android has no notion of "not asked yet" for
      // notifications, so a fresh install on 13+ reads as denied. Treating
      // that as final is what stopped the prompt appearing at all.
      check(ModelDownloader.shouldRequestNotifications(PermissionStatus.denied))
          .isTrue();
    });

    test('asks when the status is undetermined', () {
      // What iOS reports before the first ask.
      check(
        ModelDownloader.shouldRequestNotifications(
          PermissionStatus.undetermined,
        ),
      ).isTrue();
    });

    test('asks for every status that is not a yes', () {
      for (final status in PermissionStatus.values) {
        check(
          because: '$status',
          ModelDownloader.shouldRequestNotifications(status),
        ).equals(status != PermissionStatus.granted);
      }
    });
  });
}
