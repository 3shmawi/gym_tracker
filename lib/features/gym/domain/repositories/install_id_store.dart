/// A random id made at first launch and kept in secure storage. It is not a
/// device identifier: a reinstall makes a new one. The server binds a code to
/// the first one that redeems it.
abstract interface class InstallIdStore {
  Future<String> get();
}
