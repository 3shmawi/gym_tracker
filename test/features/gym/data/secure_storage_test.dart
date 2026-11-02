import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/data/datasources/secret_store.dart';
import 'package:gym_tracker/features/gym/data/datasources/secure_install_id_store.dart';
import 'package:gym_tracker/features/gym/data/datasources/secure_local_storage.dart';

/// Memory instead of the Keychain; can be told to break.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool broken = false;

  void _check() {
    if (broken) throw PlatformException(code: 'keychain', message: 'no access');
  }

  @override
  Future<String?> read(String key) async {
    _check();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _check();
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _check();
    values.remove(key);
  }
}

void main() {
  group('SecureLocalStorage (the Supabase session)', () {
    late MemorySecretStore store;

    setUp(() => store = MemorySecretStore());

    test('keeps the session in the secret store, under one key', () async {
      final storage = SecureLocalStorage(store);
      expect(await storage.hasAccessToken(), isFalse);
      await storage.persistSession('{"refresh_token":"r"}');
      expect(store.values.keys, [SecureLocalStorage.sessionKey]);
      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), '{"refresh_token":"r"}');
      await storage.removePersistedSession();
      expect(await storage.accessToken(), isNull);
      expect(store.values, isEmpty);
    });

    test('an empty value is no session', () async {
      store.values[SecureLocalStorage.sessionKey] = '';
      expect(await SecureLocalStorage(store).hasAccessToken(), isFalse);
    });

    test(
      'a store that cannot be opened means "no session", never a crash',
      () async {
        store.broken = true;
        final storage = SecureLocalStorage(store);
        expect(await storage.accessToken(), isNull);
        expect(await storage.hasAccessToken(), isFalse);
        await storage.persistSession('x');
        await storage.removePersistedSession();
      },
    );

    test('a session left by an earlier install is dropped', () async {
      store.values[SecureLocalStorage.sessionKey] = 'old';
      await SecureLocalStorage(
        store,
        isFreshInstall: () async => true,
      ).initialize();
      expect(store.values, isEmpty);
    });

    test('a normal launch keeps the session', () async {
      store.values[SecureLocalStorage.sessionKey] = 'mine';
      await SecureLocalStorage(
        store,
        isFreshInstall: () async => false,
      ).initialize();
      expect(store.values[SecureLocalStorage.sessionKey], 'mine');
      await SecureLocalStorage(store).initialize();
      expect(store.values[SecureLocalStorage.sessionKey], 'mine');
    });
  });

  group('SecureInstallIdStore', () {
    final v4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('makes a random version 4 id once and keeps it', () async {
      final store = MemorySecretStore();
      final ids = SecureInstallIdStore(store);
      final first = await ids.get();
      expect(first, matches(v4));
      expect(await ids.get(), first);
      expect(store.values[SecureInstallIdStore.storeKey], first);
      // A new process reads the same one.
      expect(await SecureInstallIdStore(store).get(), first);
    });

    test('two phones do not share an id', () async {
      final a = await SecureInstallIdStore(MemorySecretStore()).get();
      final b = await SecureInstallIdStore(MemorySecretStore()).get();
      expect(a, isNot(b));
    });

    test('a stored value that is not an id is replaced', () async {
      final store = MemorySecretStore()
        ..values[SecureInstallIdStore.storeKey] = 'not-a-uuid';
      final id = await SecureInstallIdStore(store).get();
      expect(id, matches(v4));
      expect(store.values[SecureInstallIdStore.storeKey], id);
    });

    test(
      'a store that cannot be opened still gives an id for this launch',
      () async {
        final store = MemorySecretStore()..broken = true;
        final ids = SecureInstallIdStore(store, random: Random(1));
        final id = await ids.get();
        expect(id, matches(v4));
        expect(await ids.get(), id);
      },
    );
  });
}
