import Flutter
import UIKit

/// A hidden scroll view whose pan gesture only begins inside regions registered from Dart.
///
/// UIKit drags the real keyboard for any scroll view with `.interactive` dismiss, so moving this
/// view's pan recognizer onto the Flutter view gives Flutter content native interactive dismiss
/// through public API only.
final class RegionScrollView: UIScrollView {
  /// Global rects, in the Flutter view's points, where a dismiss drag may start.
  var regions: [Int: CGRect] = [:]

  /// Whether the keyboard is on screen; with it hidden there is nothing to drag.
  var keyboardVisible: () -> Bool = { false }

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === panGestureRecognizer, let host = gestureRecognizer.view else {
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    guard keyboardVisible() else { return false }
    let location = gestureRecognizer.location(in: host)
    return regions.values.contains { $0.contains(location) }
  }
}

public class KeyboardControllerPlugin: NSObject, FlutterPlugin {
  /// The hidden scroll view's content height; only needs to exceed the screen so UIKit treats
  /// the pan as a scroll.
  private static let scrollContentHeight: CGFloat = 100_000

  /// Height changes smaller than this, in points, are not reported.
  private static let heightTolerance: CGFloat = 0.5

  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private weak var hostView: UIView?
  private var scrollView: RegionScrollView?
  private var displayLink: CADisplayLink?
  private var dragBaseline: CGFloat = 0
  private var lastReported: CGFloat = 0
  private var reportedDrag = false
  /// The keyboard height from the latest will-change notification for this app's keyboard.
  private var announcedHeight: CGFloat = 0

  /// Regions are kept here so ones registered before the view exists still apply.
  private var regions: [Int: CGRect] = [:] {
    didSet { scrollView?.regions = regions }
  }

  init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
    super.init()
    NotificationCenter.default.addObserver(
      self, selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "keyboard_controller", binaryMessenger: registrar.messenger())
    let instance = KeyboardControllerPlugin(channel: channel, registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    NotificationCenter.default.removeObserver(self)
    stopDisplayLink()
    if let pan = scrollView?.panGestureRecognizer { hostView?.removeGestureRecognizer(pan) }
    scrollView?.removeFromSuperview()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "install":
      // Dart sends this once per new scope, before any region; regions left over from a
      // previous isolate (hot restart) belong to screens that no longer exist.
      regions.removeAll()
      install()
      // The plugin's iOS 15 minimum guarantees the keyboard layout guide; if the Flutter view is
      // not ready yet, the next setRegion installs it.
      result(true)
    case "setRegion":
      guard let id = arguments["id"] as? Int else { return result(nil) }
      regions[id] = CGRect(
        x: (arguments["left"] as? Double) ?? 0, y: (arguments["top"] as? Double) ?? 0,
        width: (arguments["width"] as? Double) ?? 0, height: (arguments["height"] as? Double) ?? 0)
      install()
      result(nil)
    case "removeRegion":
      if let id = arguments["id"] as? Int { regions.removeValue(forKey: id) }
      result(nil)
    case "startControl", "setControlledInset", "finishControl":
      // Android only: iOS lets UIKit move the keyboard.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Finds the Flutter view; the registrar's controller can be unset in scene-based apps, so
  /// fall back to the window hierarchy.
  private func findFlutterView() -> UIView? {
    if let view = registrar?.viewController?.view { return view }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let controller = window.rootViewController as? FlutterViewController {
          return controller.view
        }
      }
    }
    return nil
  }

  private func install() {
    guard scrollView == nil, let view = findFlutterView() else { return }
    hostView = view
    // The guide is created lazily and reads as zero until laid out; create and lay it out now
    // so the first drag starts from a real baseline.
    _ = view.keyboardLayoutGuide
    view.layoutIfNeeded()
    let scroll = RegionScrollView(frame: view.bounds)
    scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    scroll.keyboardDismissMode = .interactive
    scroll.alwaysBounceVertical = true
    // The engine's own hidden scroll view handles status-bar taps; UIKit ignores the tap when
    // more than one scroll view claims it.
    scroll.scrollsToTop = false
    scroll.contentSize = CGSize(width: 1, height: Self.scrollContentHeight)
    scroll.contentOffset = CGPoint(x: 0, y: Self.scrollContentHeight / 2)
    scroll.isUserInteractionEnabled = false
    scroll.keyboardVisible = { [weak self] in
      (self?.announcedHeight ?? 0) > Self.heightTolerance
    }
    view.insertSubview(scroll, at: 0)
    let pan = scroll.panGestureRecognizer
    // Flutter keeps receiving the touches, so its own scrolling, taps and selection still work.
    pan.cancelsTouchesInView = false
    pan.delaysTouchesBegan = false
    pan.delaysTouchesEnded = false
    pan.addTarget(self, action: #selector(panChanged(_:)))
    view.addGestureRecognizer(pan)
    scroll.regions = regions
    scrollView = scroll
  }

  private func keyboardHeight(in view: UIView) -> CGFloat {
    return view.bounds.height - view.keyboardLayoutGuide.layoutFrame.minY
  }

  private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
  }

  @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
    guard let view = hostView else { return }
    switch recognizer.state {
    case .began:
      dragBaseline = keyboardHeight(in: view)
      lastReported = dragBaseline
      reportedDrag = false
      stopDisplayLink()
      let link = CADisplayLink(target: self, selector: #selector(tick))
      link.add(to: .main, forMode: .common)
      displayLink = link
    case .ended, .cancelled, .failed:
      stopDisplayLink()
      if reportedDrag {
        reportedDrag = false
        channel.invokeMethod("interactiveEnd", arguments: [String: Any]())
      }
    default:
      break
    }
  }

  @objc private func tick() {
    guard let view = hostView else { return }
    // The layout guide follows the keyboard every frame during an interactive drag, while
    // UIKit posts no frame notifications until the finger lifts.
    let height = keyboardHeight(in: view)
    if !reportedDrag && abs(height - dragBaseline) < Self.heightTolerance { return }
    if reportedDrag && abs(height - lastReported) < Self.heightTolerance { return }
    reportedDrag = true
    lastReported = height
    channel.invokeMethod("interactive", arguments: ["height": Double(height)])
  }

  @objc private func keyboardWillChangeFrame(_ notification: Notification) {
    guard let view = hostView, let info = notification.userInfo,
      let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
    else { return }
    // In iPad Split View the other app's keyboard is announced too; it does not cover us.
    if let isLocal = info[UIResponder.keyboardIsLocalUserInfoKey] as? Bool, !isLocal { return }
    let space = view.window?.screen.coordinateSpace ?? UIScreen.main.coordinateSpace
    let frameInView = view.convert(endFrame, from: space)
    let height = max(0, view.bounds.height - frameInView.minY)
    announcedHeight = height
    let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0
    channel.invokeMethod(
      "keyboardWillChange",
      arguments: ["height": Double(height), "durationMs": duration * 1000])
  }
}
