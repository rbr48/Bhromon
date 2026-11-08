import 'dart:typed_data';

import 'package:bhromon/features/chat/domain/e2ee/e2ee_exceptions.dart';

/// The Olm pre-key message format version (session version 1, decision D10).
const int _preKeyVersion = 3;

/// The one-time key a pre-key message was made with (E2EE_DESIGN.md, section 6).
///
/// An Olm pre-key message is one version byte, then protobuf fields: the one-time
/// key (field 1), the base key (field 2), the identity key (field 3) and the
/// embedded message (field 4). The receiver reads the one-time key before it
/// decrypts, so the server copy can be removed first. Only the field's presence and
/// length are checked here. The session logic checks the rest.
Uint8List oneTimeKeyOfPreKeyMessage(Uint8List message) {
  if (message.isEmpty || message[0] != _preKeyVersion) {
    throw const E2eeFormatException('the message is not a pre-key message');
  }
  var offset = 1;
  while (offset < message.length) {
    final tag = message[offset];
    offset++;
    final field = tag >> 3;
    if (tag & 0x07 != 2) {
      throw const E2eeFormatException('a pre-key message field is not bytes');
    }
    final (length, afterLength) = _readLength(message, offset);
    offset = afterLength;
    if (length > message.length - offset) {
      throw const E2eeFormatException(
          'a pre-key message field runs past its end');
    }
    if (field == 1) {
      if (length != 32) {
        throw const E2eeFormatException('the one-time key is not 32 bytes');
      }
      return Uint8List.fromList(message.sublist(offset, offset + length));
    }
    offset += length;
  }
  throw const E2eeFormatException('the pre-key message has no one-time key');
}

/// A protobuf varint, read from [start]. Returns the value and the offset after it.
(int, int) _readLength(Uint8List bytes, int start) {
  var value = 0;
  var shift = 0;
  var offset = start;
  while (true) {
    if (offset >= bytes.length || shift > 28) {
      throw const E2eeFormatException('a pre-key message length is malformed');
    }
    final byte = bytes[offset];
    offset++;
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) {
      return (value, offset);
    }
    shift += 7;
  }
}
