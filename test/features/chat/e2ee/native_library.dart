import 'dart:io';

/// The path of the built `libe2ee_olm` for the FFI tests. Set `E2EE_OLM_LIBRARY`
/// to it (see native/e2ee_olm). The FFI tests are skipped when it is not set.
String? nativeLibraryPath() {
  final path = Platform.environment['E2EE_OLM_LIBRARY'];
  return path == null || path.isEmpty ? null : path;
}

/// The reason given to a skipped FFI test.
const String nativeLibrarySkipReason =
    'set E2EE_OLM_LIBRARY to the built libe2ee_olm (native/e2ee_olm)';
