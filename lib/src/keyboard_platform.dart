import 'package:flutter/services.dart';

/// The method channel between the Dart widgets and the iOS and Android keyboard code.
///
/// All heights crossing the channel are logical pixels.
class KeyboardPlatform {
  /// Creates the channel wrapper and starts listening for native events.
  KeyboardPlatform({MethodChannel channel = const MethodChannel(channelName)})
    : _channel = channel {
    _channel.setMethodCallHandler(_handle);
  }

  /// The channel name shared with the native plugins.
  static const String channelName = 'keyboard_controller';

  final MethodChannel _channel;

  /// Called when the keyboard is about to animate to a new height.
  void Function(double height, Duration duration)? onWillChange;

  /// Called every frame while a finger drags the keyboard on iOS.
  ValueChanged<double>? onInteractive;

  /// Called when the finger that dragged the keyboard on iOS lifts.
  VoidCallback? onInteractiveEnd;

  /// Called when Android takes keyboard control back before Dart released it.
  VoidCallback? onControlEnded;

  Future<Object?> _handle(MethodCall call) async {
    final arguments = (call.arguments as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
    switch (call.method) {
      case 'keyboardWillChange':
        onWillChange?.call(
          (arguments['height']! as num).toDouble(),
          Duration(milliseconds: (arguments['durationMs']! as num).round()),
        );
      case 'interactive':
        onInteractive?.call((arguments['height']! as num).toDouble());
      case 'interactiveEnd':
        onInteractiveEnd?.call();
      case 'controlEnded':
        onControlEnded?.call();
    }
    return null;
  }

  // Platforms without the native side (tests, web, desktop) fall back to engine insets only.
  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  /// Prepares the native side; safe to call more than once.
  ///
  /// Returns whether this device supports interactive dismiss (iOS 15+, Android API 30+).
  Future<bool> install() async => await _invoke<bool>('install') ?? false;

  /// Allows interactive dismiss for drags starting inside [rect], in global logical pixels.
  Future<void> setRegion(int id, Rect rect) {
    return _invoke<void>('setRegion', <String, Object>{
      'id': id,
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    });
  }

  /// Removes a region added with [setRegion].
  Future<void> removeRegion(int id) => _invoke<void>('removeRegion', <String, Object>{'id': id});

  /// Takes control of the Android keyboard position.
  ///
  /// Returns the fully open keyboard height, or null when control is unavailable.
  Future<double?> startControl() async {
    final shown = await _invoke<num>('startControl');
    return shown?.toDouble();
  }

  /// Moves the controlled Android keyboard to [height].
  Future<void> setControlledInset(double height) {
    return _invoke<void>('setControlledInset', <String, Object>{'height': height});
  }

  /// Releases control, leaving the keyboard shown or hidden.
  Future<void> finishControl({required bool show}) {
    return _invoke<void>('finishControl', <String, Object>{'show': show});
  }

  /// Stops listening for native events.
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
