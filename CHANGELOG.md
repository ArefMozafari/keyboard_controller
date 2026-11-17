## 0.1.1

- `KeyboardChatView` no longer shows messages through the bottom safe area below the composer
  (the gesture bar or home indicator strip) while the list is scrolled.

## 0.1.0

- `KeyboardChatView`: reversed chat list with a composer that rides the keyboard, interactive
  dismiss, four lift behaviours (`always`, `whenAtEnd`, `persistent`, `never`), streaming follow,
  a stable reading position, and `pinToTop` for AI chats.
- `ChatScrollController` with `isAtEnd`, `animateToLatest`, `pinToTop` and `clearPin`.
- `KeyboardScope` keyboard state: height, target height, progress and phase.
- `KeyboardStickyView`, `KeyboardDismissRegion` and `KeyboardHoldScrollPhysics` for custom
  layouts.
- iOS 15+ and Android API 30+ interactive dismiss through public platform APIs; dismiss on drag
  below Android API 30.
