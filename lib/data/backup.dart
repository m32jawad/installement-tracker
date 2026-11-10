import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/app_log.dart';
import 'database.dart';

/// Backup = one .zip holding the SQLite database and every photo.
class BackupService {
  final String dbPath;
  final Directory photoDir;
  BackupService(this.dbPath, this.photoDir);

  static const marker = 'installment_tracker_backup.txt';

  /// Writes a backup zip to [outDir] and returns it. sqflite uses a rollback
  /// journal (not WAL), so copying the file inside an exclusive transaction
  /// gives a consistent snapshot on every Android version (VACUUM INTO needs
  /// SQLite 3.27, newer than Android 7-10 ship).
  Future<File> createBackup(Database db, Directory outDir) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final snapshot = File(p.join(outDir.path, 'snapshot_$stamp.db'));
    if (await snapshot.exists()) await snapshot.delete();
    await db.transaction((tx) async {
      await File(dbPath).copy(snapshot.path);
    }, exclusive: true);

    final archive = Archive();
    archive.add(ArchiveFile.string(marker, 'schema=$schemaVersion\ncreated=$stamp\n'));
    archive.add(ArchiveFile.bytes(dbFileName, await snapshot.readAsBytes()));
    var photoCount = 0;
    if (await photoDir.exists()) {
      await for (final f in photoDir.list()) {
        if (f is File) {
          archive.add(ArchiveFile.bytes(
              'photos/${p.basename(f.path)}', await f.readAsBytes()));
          photoCount++;
        }
      }
    }
    final zip = File(p.join(outDir.path, 'InstallmentTracker_backup_$stamp.zip'));
    await zip.writeAsBytes(ZipEncoder().encodeBytes(archive));
    await snapshot.delete();
    AppLog.info('Backup created: ${zip.path} ($photoCount photos, '
        '${await zip.length()} bytes)');
    return zip;
  }

  /// Validates and restores a backup zip. The caller must close the open
  /// database first and re-open it afterwards.
  Future<void> restoreBackup(List<int> zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    ArchiveFile? dbEntry;
    var hasMarker = false;
    for (final f in archive.files) {
      if (f.name == dbFileName) dbEntry = f;
      if (f.name == marker) hasMarker = true;
    }
    if (!hasMarker || dbEntry == null) {
      throw const FormatException(
          'This file is not an Installment Tracker backup.');
    }
    final dbBytes = dbEntry.readBytes();
    if (dbBytes == null || dbBytes.length < 100 ||
        String.fromCharCodes(dbBytes.sublist(0, 15)) != 'SQLite format 3') {
      throw const FormatException('The backup database is damaged.');
    }
    // Keep the current database until the new one is fully written.
    final tmp = File('$dbPath.restore');
    await tmp.writeAsBytes(dbBytes, flush: true);
    if (await photoDir.exists()) await photoDir.delete(recursive: true);
    await photoDir.create(recursive: true);
    var photoCount = 0;
    for (final f in archive.files) {
      if (f.isFile && f.name.startsWith('photos/')) {
        final name = p.basename(f.name);
        if (name.isEmpty || name.contains('..')) continue;
        await File(p.join(photoDir.path, name)).writeAsBytes(f.content);
        photoCount++;
      }
    }
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final side = File('$dbPath$suffix');
      if (await side.exists()) await side.delete();
    }
    await tmp.rename(dbPath);
    AppLog.info('Backup restored ($photoCount photos)');
  }
}
