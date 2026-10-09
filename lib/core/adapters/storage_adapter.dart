import 'dart:typed_data';

enum StorageFailure { notConfigured, tooLarge, wrongType, badPath, notFound }

class StoredFile {
  final String path;
  final String url;
  final int bytes;
  const StoredFile(this.path, this.url, this.bytes);
}

/// Same limits as storage.rules: images only, under 5 MB.
const maxUploadBytes = 5 * 1024 * 1024;
const allowedUploadTypes = {'image/jpeg', 'image/png', 'image/webp'};

/// LATER(paid): Firebase Storage (Blaze plan). Photos for RC, papers, trip
/// proof. Paths look like `users/{uid}/rc/{file}`; `..` and a leading `/` are refused.
abstract class FileStore {
  Future<(StoredFile?, StorageFailure?)> put(String path, Uint8List bytes, String contentType);
  Future<StorageFailure?> delete(String path);
}

bool safeStoragePath(String p) => p.isNotEmpty && !p.startsWith('/') && !p.contains('..') && !p.contains('//') && p.length <= 200;

class NoFileStore implements FileStore {
  const NoFileStore();
  @override
  Future<(StoredFile?, StorageFailure?)> put(String path, Uint8List bytes, String contentType) async => (null, StorageFailure.notConfigured);
  @override
  Future<StorageFailure?> delete(String path) async => StorageFailure.notConfigured;
}

class FakeFileStore implements FileStore {
  final Map<String, Uint8List> files = {};

  @override
  Future<(StoredFile?, StorageFailure?)> put(String path, Uint8List bytes, String contentType) async {
    if (!safeStoragePath(path)) return (null, StorageFailure.badPath);
    if (!allowedUploadTypes.contains(contentType)) return (null, StorageFailure.wrongType);
    if (bytes.length > maxUploadBytes) return (null, StorageFailure.tooLarge);
    files[path] = bytes;
    return (StoredFile(path, 'fake://$path', bytes.length), null);
  }

  @override
  Future<StorageFailure?> delete(String path) async => files.remove(path) == null ? StorageFailure.notFound : null;
}
