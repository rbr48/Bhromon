/// Whether switching channels must clear the composer text of the channel being
/// left.
///
/// Starting an edit writes the message text into the draft of the channel it
/// started in. Leaving that channel ends the edit, so the text must not stay
/// behind as a plain draft, where sending it would post a duplicate instead of
/// an edit. Tapping the channel that is already open clears nothing.
bool shouldClearEditDraftOnSwitch({
  required bool isEditing,
  required String fromChannelId,
  required String toChannelId,
}) =>
    isEditing && fromChannelId != toChannelId;
