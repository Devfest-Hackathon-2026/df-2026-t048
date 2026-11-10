enum LoginProvider { google, apple }

final class CloudSnapshot {
  const CloudSnapshot({
    required this.payload,
    required this.revision,
    required this.updatedAt,
  });
  final String payload, revision;
  final DateTime updatedAt;
}

abstract interface class CloudBackupPort {
  bool get configured;
  bool get signedIn;
  Future<void> signIn(LoginProvider provider);
  Future<void> signOut();
  Future<CloudSnapshot?> fetch();
  Future<void> save(String payload, {String? expectedRevision});
  Future<void> delete(String expectedRevision);
}
