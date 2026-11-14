// What the system back button and the picture-in-picture window do on the call screen. Pure
// rules, so they are tested without the screen or a phone.

/// What pressing back does on the call screen.
enum CallBackAction {
  /// The call is still on, on Android: the app minimizes and the call carries on.
  minimize,

  /// The call is over, or the phone is not Android: the screen is left and the call ends, as it
  /// always has.
  leave,
}

/// Back minimizes a call that is still on, on Android, the same as Home does. Once the call is
/// over, or anywhere else, back leaves the screen.
CallBackAction callBackActionFor({
  required bool onAndroid,
  required bool callOver,
}) {
  return onAndroid && !callOver
      ? CallBackAction.minimize
      : CallBackAction.leave;
}

/// Whether the phone may shrink the call into picture-in-picture when the user leaves the app.
/// Only a video call that is connected, and not over, may.
bool callShrinksToPip({
  required bool videoMode,
  required bool connected,
  required bool callOver,
}) {
  return videoMode && connected && !callOver;
}
