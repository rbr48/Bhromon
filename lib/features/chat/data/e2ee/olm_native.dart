// The Olm engine. On the native platforms it is the library in olm_native_ffi.dart;
// on the web it is the stub in olm_native_unsupported.dart.
export 'olm_native_unsupported.dart'
    if (dart.library.ffi) 'olm_native_ffi.dart';
