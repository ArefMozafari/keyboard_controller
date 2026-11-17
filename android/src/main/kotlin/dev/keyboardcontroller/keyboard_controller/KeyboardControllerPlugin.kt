package dev.keyboardcontroller.keyboard_controller

import android.app.Activity
import android.graphics.Insets
import android.os.Build
import android.os.CancellationSignal
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsAnimation
import android.view.WindowInsetsAnimationControlListener
import android.view.WindowInsetsAnimationController
import android.view.animation.LinearInterpolator
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.math.roundToInt

/**
 * Drives the Android keyboard for interactive dismiss and reports where it is heading.
 *
 * Position during a drag comes from Dart, which asks for each inset; the engine already reflects
 * controlled insets in `viewInsets`. Target heights come from a 0×0 view's insets animation
 * callback, so the FlutterView's own callback is never replaced.
 */
class KeyboardControllerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var tracker: View? = null
    private var controller: WindowInsetsAnimationController? = null
    private var controlPending = false

    private val density: Float
        get() = activity?.resources?.displayMetrics?.density ?: 1f

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "keyboard_controller")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) attachTracker(binding.activity)
    }

    override fun onDetachedFromActivity() {
        detachTracker()
        // A drag interrupted by detach must not leave the keyboard half open.
        val finishing = controller
        controller = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) finishing?.finish(true)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // Inset control, and so interactive dismiss, needs API 30.
            "install" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            // iOS only: on Android dismiss regions are tracked in Dart.
            "setRegion", "removeRegion" -> result.success(null)
            "startControl" -> startControl(result)
            "setControlledInset" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val height = call.argument<Number>("height")?.toFloat() ?: 0f
                    controller?.setInsetsAndAlpha(
                        Insets.of(0, 0, 0, (height * density).roundToInt()),
                        1f,
                        0f,
                    )
                }
                result.success(null)
            }
            "finishControl" -> {
                // Cleared before finishing, so onFinished can tell this release from the system
                // taking control back.
                val finishing = controller
                controller = null
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    finishing?.finish(call.argument<Boolean>("show") ?: true)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startControl(result: Result) {
        val window = activity?.window
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || window == null || controlPending) {
            result.success(null)
            return
        }
        controlPending = true
        var replied = false
        window.insetsController?.controlWindowInsetsAnimation(
            WindowInsets.Type.ime(),
            -1,
            LinearInterpolator(),
            CancellationSignal(),
            object : WindowInsetsAnimationControlListener {
                override fun onReady(animationController: WindowInsetsAnimationController, types: Int) {
                    controller = animationController
                    controlPending = false
                    if (!replied) {
                        replied = true
                        result.success(animationController.shownStateInsets.bottom / density.toDouble())
                    }
                }

                override fun onFinished(animationController: WindowInsetsAnimationController) {
                    // Still ours means Dart never released it: the system took it back.
                    if (controller == animationController) {
                        controller = null
                        channel.invokeMethod("controlEnded", null)
                    }
                }

                override fun onCancelled(animationController: WindowInsetsAnimationController?) {
                    controller = null
                    controlPending = false
                    if (!replied) {
                        replied = true
                        result.success(null)
                    } else {
                        // Cancelled after Dart started dragging, for example when focus moved.
                        channel.invokeMethod("controlEnded", null)
                    }
                }
            },
        ) ?: run {
            controlPending = false
            result.success(null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun attachTracker(activity: Activity) {
        detachTracker()
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val view = View(activity)
        view.setWindowInsetsAnimationCallback(
            object : WindowInsetsAnimation.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
                override fun onProgress(
                    insets: WindowInsets,
                    runningAnimations: MutableList<WindowInsetsAnimation>,
                ): WindowInsets = insets

                override fun onStart(
                    animation: WindowInsetsAnimation,
                    bounds: WindowInsetsAnimation.Bounds,
                ): WindowInsetsAnimation.Bounds {
                    val isIme = animation.typeMask and WindowInsets.Type.ime() != 0
                    // A controlled animation is driven from Dart, which already knows its target.
                    if (isIme && controller == null && !controlPending) {
                        // In onStart the root insets already hold the animation's end state.
                        val insets = view.rootWindowInsets
                        val visible = insets?.isVisible(WindowInsets.Type.ime()) ?: false
                        val pixels = if (visible) insets.getInsets(WindowInsets.Type.ime()).bottom else 0
                        channel.invokeMethod(
                            "keyboardWillChange",
                            mapOf(
                                "height" to pixels / density.toDouble(),
                                "durationMs" to animation.durationMillis,
                            ),
                        )
                    }
                    return bounds
                }
            },
        )
        content.addView(view, ViewGroup.LayoutParams(0, 0))
        tracker = view
    }

    private fun detachTracker() {
        val view = tracker ?: return
        (view.parent as? ViewGroup)?.removeView(view)
        tracker = null
    }
}
