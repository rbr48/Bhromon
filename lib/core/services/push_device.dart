import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The Firestore document id for one device's push token, under
/// `fcm_tokens/{uid}/devices`. A hash keeps the id short and clear of the
/// characters a document id cannot hold.
String pushDeviceId(String token) =>
    sha256.convert(utf8.encode(token)).toString();
