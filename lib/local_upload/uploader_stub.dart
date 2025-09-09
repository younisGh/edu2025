// Stub uploader for non-IO platforms (e.g., web). Methods throw by default.

Future<String> uploadPathToFirebase(String filePath, String storagePath,
    {String contentType = 'application/octet-stream'}) async {
  throw UnsupportedError('uploadPathToFirebase is only supported on IO platforms');
}
