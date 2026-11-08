import 'package:bhromon/features/chat/domain/e2ee/olm_engine.dart';

/// The web has no native library, so end-to-end encryption is not available
/// there (E2EE_DESIGN.md, decision D3). Calling this on the web throws.
OlmEngine openOlmEngine({String? libraryPath}) {
  throw UnsupportedError(
    'End-to-end encryption needs the native library, which the web does not have.',
  );
}
