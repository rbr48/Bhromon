/// What a person can do with a message in a chat (E2EE_DESIGN.md, section 11, M4
/// item 7). An encrypted chat offers only the actions its first slice supports. The
/// rules refuse the others, so the app does not offer them either.
enum ChatAction {
  reply,
  edit,
  pin,
  star,
  forward,
  react,
  copy,
  deleteForMe,
  deleteForEveryone,
}

/// Whether [action] is offered in a chat. A plaintext chat offers every action. An
/// encrypted chat offers copying the text this device has read, and deleting a message
/// for this person only.
bool chatActionAllowed(ChatAction action, {required bool encrypted}) {
  if (!encrypted) return true;
  return switch (action) {
    ChatAction.copy || ChatAction.deleteForMe => true,
    _ => false,
  };
}
