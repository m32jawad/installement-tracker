import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Photos (CNIC, cheques, items, receipts) are copied into the app's private
/// folder, so they are only visible inside the app and travel with backups.
/// The database stores the file name only, never an absolute path.
class PhotoStore {
  final Directory dir;
  PhotoStore(this.dir);

  static final _rand = Random();

  Future<String> importFile(String sourcePath) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final name =
        '${DateTime.now().millisecondsSinceEpoch}_${_rand.nextInt(1 << 30)}$ext';
    await File(sourcePath).copy(p.join(dir.path, name));
    return name;
  }

  File file(String name) => File(p.join(dir.path, name));

  Future<void> delete(String? name) async {
    if (name == null) return;
    final f = file(name);
    if (await f.exists()) await f.delete();
  }
}
