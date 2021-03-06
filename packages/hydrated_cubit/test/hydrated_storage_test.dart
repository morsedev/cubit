import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hydrated_cubit/hydrated_cubit.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pedantic/pedantic.dart';

class MockBox extends Mock implements Box<dynamic> {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  disablePathProviderPlatformOverride = true;

  group('HydratedStorage', () {
    final cwd = Directory.current.absolute.path;
    var getTemporaryDirectoryCallCount = 0;
    const MethodChannel('plugins.flutter.io/path_provider')
      ..setMockMethodCallHandler((methodCall) async {
        if (methodCall.method == 'getTemporaryDirectory') {
          getTemporaryDirectoryCallCount++;
          return cwd;
        }
        throw UnimplementedError();
      });

    tearDownAll(() async {
      await Hive.deleteBoxFromDisk('hydrated_box');
    });

    group('build', () {
      setUp(() async {
        await (await HydratedStorage.build()).clear();
        getTemporaryDirectoryCallCount = 0;
      });

      test('calls getTemporaryDirectory when storageDirectory is null',
          () async {
        await HydratedStorage.build();
        expect(getTemporaryDirectoryCallCount, 1);
      });

      test(
          'does not call getTemporaryDirectory '
          'when storageDirectory is defined', () async {
        await HydratedStorage.build(storageDirectory: Directory(cwd));
        expect(getTemporaryDirectoryCallCount, 0);
      });

      test('reuses existing instance when called multiple times', () async {
        final instanceA = await HydratedStorage.build();
        final beforeCount = getTemporaryDirectoryCallCount;
        final instanceB = await HydratedStorage.build();
        final afterCount = getTemporaryDirectoryCallCount;
        expect(beforeCount, afterCount);
        expect(instanceA, instanceB);
      });

      test('calls Hive.init with correct directory', () async {
        await HydratedStorage.build();
        final box = Hive.box<dynamic>('hydrated_box');
        final directory = await getTemporaryDirectory();
        expect(box, isNotNull);
        expect(box.path, '${directory.path}/hydrated_box.hive');
      });
    });

    group('default constructor', () {
      const key = '__key__';
      const value = '__value__';
      Box box;
      Storage storage;

      setUp(() {
        box = MockBox();
        storage = HydratedStorage(box);
      });

      group('read', () {
        test('returns null when box is not open', () {
          when(box.isOpen).thenReturn(false);
          expect(storage.read(key), isNull);
        });

        test('returns correct value when box is open', () {
          when(box.isOpen).thenReturn(true);
          when<dynamic>(box.get(any)).thenReturn(value);
          expect(storage.read(key), value);
          verify<dynamic>(box.get(key)).called(1);
        });
      });

      group('write', () {
        test('does nothing when box is not open', () async {
          when(box.isOpen).thenReturn(false);
          await storage.write(key, value);
          verifyNever(box.put(any, any));
        });

        test('puts key/value in box when box is open', () async {
          when(box.isOpen).thenReturn(true);
          await storage.write(key, value);
          verify(box.put(key, value)).called(1);
        });
      });

      group('delete', () {
        test('does nothing when box is not open', () async {
          when(box.isOpen).thenReturn(false);
          await storage.delete(key);
          verifyNever(box.delete(any));
        });

        test('puts key/value in box when box is open', () async {
          when(box.isOpen).thenReturn(true);
          await storage.delete(key);
          verify(box.delete(key)).called(1);
        });
      });

      group('clear', () {
        test('does nothing when box is not open', () async {
          when(box.isOpen).thenReturn(false);
          await storage.clear();
          verifyNever(box.deleteFromDisk());
        });

        test('deletes box when box is open', () async {
          when(box.isOpen).thenReturn(true);
          await storage.clear();
          verify(box.deleteFromDisk()).called(1);
        });
      });
    });

    group('During heavy load', () {
      test('writes key/value pairs correctly', () async {
        const token = 'token';
        var hydratedStorage = await HydratedStorage.build(
          storageDirectory: Directory(cwd),
        );
        await Stream.fromIterable(
          Iterable.generate(120, (i) => i),
        ).asyncMap((i) async {
          final record = Iterable.generate(
            i,
            (i) => Iterable.generate(i, (j) => 'Point($i,$j);').toList(),
          ).toList();

          unawaited(hydratedStorage.write(token, record));

          hydratedStorage = await HydratedStorage.build(
            storageDirectory: Directory(cwd),
          );

          final written = hydratedStorage.read(token) as List<List<String>>;
          expect(written, isNotNull);
          expect(written, record);
        }).drain<dynamic>();
      });
    });
  });
}
