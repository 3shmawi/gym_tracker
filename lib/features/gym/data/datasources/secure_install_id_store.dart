import 'dart:math';

import 'package:gym_tracker/features/gym/data/datasources/secret_store.dart';
import 'package:gym_tracker/features/gym/domain/repositories/install_id_store.dart';

/// Makes a random version-4 UUID at first use and keeps it in the secret
/// store. Not a hardware id: reinstalling makes a new one.
class SecureInstallIdStore implements InstallIdStore {
  new(this._store, {Random? random}) : _random = random ?? Random.secure();

  static const storeKey = 'azm.install_id';

  final SecretStore _store;
  final Random _random;
  String? _cached;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  @override
  Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    String? stored;
    try {
      stored = await _store.read(storeKey);
    } on Object {
      stored = null;
    }
    if (stored != null && _uuid.hasMatch(stored)) return _cached = stored;
    final fresh = _newUuid();
    try {
      await _store.write(storeKey, fresh);
    } on Object {
      // Not saved: this launch still has an id; the next one makes another.
    }
    return _cached = fresh;
  }

  String _newUuid() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10).join()}';
  }
}
