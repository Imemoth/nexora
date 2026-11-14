import 'dart:io';

/// Where each account's local database lives. The local workspace
/// (`nexora.db`, used signed out) is a different file from every account's
/// database, and one account's file is never opened for another account, so
/// synchronized data of two accounts can never meet in one SQLite file.
final class AccountPaths {
  AccountPaths(this.root);

  /// The Nexora data folder, for example `%LOCALAPPDATA%\Nexora`.
  final Directory root;

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// True for a well-formed user id (the only thing that may become a folder name).
  static bool isValidUserId(String userId) => _uuid.hasMatch(userId);

  /// The database file of [userId]. Throws [ArgumentError] for anything that is
  /// not a UUID, so a hostile or damaged id can never escape the folder.
  File databaseFor(String userId) {
    final id = userId.toLowerCase();
    if (!isValidUserId(id)) {
      throw ArgumentError.value(userId, 'userId', 'not a user id');
    }
    final s = Platform.pathSeparator;
    return File('${root.path}${s}accounts$s$id${s}nexora.db');
  }
}
