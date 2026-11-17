import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/src/keyboard_platform.dart';

const codec = StandardMethodCodec();
const channel = MethodChannel(KeyboardPlatform.channelName);

Future<void> sendFromNative(String method, Map<String, Object?> arguments) {
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    KeyboardPlatform.channelName,
    codec.encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeyboardPlatform', () {
    late List<MethodCall> calls;
    late KeyboardPlatform platform;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls.add(call);
          return call.method == 'startControl' ? 291.5 : null;
        },
      );
      platform = KeyboardPlatform();
    });

    tearDown(() {
      platform.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test('should decode keyboardWillChange into height and duration', () async {
      double? height;
      Duration? duration;
      platform.onWillChange = (value, length) {
        height = value;
        duration = length;
      };

      await sendFromNative('keyboardWillChange', {'height': 336.0, 'durationMs': 250});

      expect(height, 336);
      expect(duration, const Duration(milliseconds: 250));
    });

    test('should decode controlEnded', () async {
      var ended = false;
      platform.onControlEnded = () => ended = true;

      await sendFromNative('controlEnded', {});

      expect(ended, isTrue);
    });

    test('should decode interactive and interactiveEnd', () async {
      final heights = <double>[];
      var ended = false;
      platform.onInteractive = heights.add;
      platform.onInteractiveEnd = () => ended = true;

      await sendFromNative('interactive', {'height': 120.0});
      await sendFromNative('interactiveEnd', {});

      expect(heights, [120]);
      expect(ended, isTrue);
    });

    test('should send setRegion with rect fields', () async {
      await platform.setRegion(7, const Rect.fromLTWH(0, 100, 390, 500));

      expect(calls.single.method, 'setRegion');
      expect(calls.single.arguments, {
        'id': 7,
        'left': 0.0,
        'top': 100.0,
        'width': 390.0,
        'height': 500.0,
      });
    });

    test('should return the shown height from startControl', () async {
      expect(await platform.startControl(), 291.5);
    });

    test('should send controlled inset and finish arguments', () async {
      await platform.setControlledInset(100);
      await platform.finishControl(show: false);

      expect(calls.map((call) => call.method), ['setControlledInset', 'finishControl']);
      expect(calls.first.arguments, {'height': 100.0});
      expect(calls.last.arguments, {'show': false});
    });

    test('should return null instead of throwing when no native side exists', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );

      expect(await platform.startControl(), isNull);
    });
  });
}
