/// Where the software keyboard is in its show and hide cycle.
enum KeyboardPhase {
  /// The keyboard is fully hidden.
  closed,

  /// The keyboard is animating towards its open height.
  opening,

  /// The keyboard rests at its open height.
  open,

  /// The keyboard is animating towards hidden.
  closing,

  /// The user's finger is moving the keyboard.
  dragging,
}
