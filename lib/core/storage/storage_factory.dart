/// Chooses the right storage backend for the current platform.
library;

import 'package:file_organizer/core/storage/io_storage_service.dart';
import 'package:file_organizer/core/storage/saf_storage_service.dart';
import 'package:file_organizer/core/storage/storage_service.dart';
import 'package:file_organizer/core/storage/unsupported_storage_service.dart';
import 'package:flutter/foundation.dart';

StorageService createStorageService() {
  if (kIsWeb) return UnsupportedStorageService();
  // Android uses the SAF channel; desktop uses dart:io.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return SafStorageService();
  }
  return IoStorageService();
}