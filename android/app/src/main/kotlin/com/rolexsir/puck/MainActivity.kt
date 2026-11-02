package com.rolexsir.puck

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's single activity, and the owner of the platform channel.
 *
 * The channel is registered here rather than in a plugin because it is four
 * calls to Android APIs that have no Flutter equivalent (see `PuckPlatform`) --
 * a plugin would add a package, a pubspec entry and a Gradle module for one
 * Kotlin file.
 */
class MainActivity : FlutterActivity() {

    private var platform: PuckPlatform? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val handler = PuckPlatform(this)
        platform = handler
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PuckPlatform.CHANNEL,
        )
        methodChannel.setMethodCallHandler(handler)
        channel = methodChannel
    }

    override fun onDestroy() {
        // Order matters: unhook the channel before the handler loses its
        // resources, so a call in flight cannot reach a disposed TTS engine.
        channel?.setMethodCallHandler(null)
        channel = null
        platform?.dispose()
        platform = null
        super.onDestroy()
    }
}
