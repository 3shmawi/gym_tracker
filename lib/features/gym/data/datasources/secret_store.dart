import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A tiny key → text store for secrets (the sign-in session, the install id).
/// An interface so tests use memory instead of the Keychain / Keystore.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Keychain on iOS, Keystore-wrapped keys on Android
/// (`flutter_secure_storage`).
///
/// iOS items use `first_unlock_this_device`: readable after the first unlock
/// (the session refreshes in the background) and never copied to another
/// phone by a backup, so a restored backup does not clone a session.
class FlutterSecretStore implements SecretStore {
  const new([
    this._storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The platform refused to open the store (no lock screen, a broken Keystore).
bool isStoreFailure(Object error) => error is PlatformException;
