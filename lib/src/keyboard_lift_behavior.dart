/// How a chat list moves when the keyboard opens or closes, named after apps that use each one.
enum KeyboardLiftBehavior {
  /// Content always moves up with the keyboard, even when scrolled into history (Telegram,
  /// WhatsApp).
  always,

  /// Content moves up only at the newest message; in history the keyboard covers the bottom of
  /// the list (ChatGPT).
  whenAtEnd,

  /// Content moves up when the keyboard opens and stays there when it closes, until the user
  /// scrolls or a prompt is pinned (Claude).
  persistent,

  /// Content never moves for the keyboard, which covers the bottom of the list (Perplexity).
  never,
}
