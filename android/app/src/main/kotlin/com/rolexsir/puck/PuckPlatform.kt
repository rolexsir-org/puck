package com.rolexsir.puck

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Bundle
import android.provider.AlarmClock
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

/**
 * The Android side of `PlatformBridge` (see
 * `lib/src/data/services/platform_bridge.dart`).
 *
 * Five capabilities, each one an Android API with no Dart equivalent:
 *
 *   * **media volume** -- `AudioManager`, on the music stream, as a percentage
 *     of the stream's own maximum because that is the only scale that means the
 *     same thing on every phone;
 *   * **app launch** -- `PackageManager` query plus a launcher intent;
 *   * **timers and alarms** -- the `AlarmClock` intents, handed to whichever
 *     clock app the phone has, never dialled in silently;
 *   * **speech** -- the platform `TextToSpeech` engine (offline on any phone
 *     with its language data installed);
 *   * **PCM playback** -- an `AudioTrack`, for the optional bundled voice.
 *
 * Every method answers `false`/`null` rather than throwing: a torch-less phone,
 * a phone with no clock app and a phone whose TTS engine is missing are all
 * ordinary states of the world, and the Flutter side turns each of them into a
 * sentence instead of an exception.
 */
class PuckPlatform(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private val context: Context = activity.applicationContext
    private val audioExecutor = Executors.newSingleThreadExecutor()

    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingUtterance: String? = null

    @Volatile
    private var playbackGeneration = 0

    @Volatile
    private var activeTrack: AudioTrack? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "volume.get" -> result.success(volumePercent())
            "volume.set" -> result.success(setVolumePercent(call.argument<Int>("percent")))
            "volume.adjust" -> result.success(adjustVolume(call.argument<Int>("steps") ?: 1))
            "volume.mute" -> result.success(setMuted(call.argument<Boolean>("muted") ?: false))
            "volume.isMuted" -> result.success(isMuted())
            "apps.open" -> openApp(call.argument<String>("name"), result)
            "clock.timer" -> result.success(startTimer(call.argument<Int>("seconds") ?: 0))
            "clock.alarm" -> result.success(
                setAlarm(call.argument<Int>("hour") ?: 0, call.argument<Int>("minute") ?: 0)
            )
            "tts.speak" -> result.success(speak(call.argument<String>("text")))
            "tts.stop" -> {
                stopSpeaking()
                result.success(true)
            }
            "tts.isSpeaking" -> result.success(ttsReady && tts?.isSpeaking == true)
            "pcm.play" -> result.success(
                playPcm(call.argument<FloatArray>("samples"), call.argument<Int>("sampleRate"))
            )
            "pcm.stop" -> {
                stopPlayback()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    // -- Volume ---------------------------------------------------------------

    private fun audioManager(): AudioManager? =
        context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

    private fun volumePercent(): Int? {
        val am = audioManager() ?: return null
        return try {
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            if (max <= 0) {
                null
            } else {
                am.getStreamVolume(AudioManager.STREAM_MUSIC) * 100 / max
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun setVolumePercent(percent: Int?): Boolean {
        val am = audioManager() ?: return false
        if (percent == null) return false
        return try {
            val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            if (max <= 0) return false
            val target = (max * percent.coerceIn(0, 100) + 50) / 100
            // Flag 0: no sound, no vibration. A phone that beeps at its new
            // volume on every "louder" is a phone that gets its microphone
            // pressed again during the beep.
            am.setStreamVolume(AudioManager.STREAM_MUSIC, target.coerceIn(0, max), 0)
            true
        } catch (e: SecurityException) {
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun adjustVolume(steps: Int): Boolean {
        val am = audioManager() ?: return false
        if (steps == 0) return true
        return try {
            val direction = if (steps > 0) {
                AudioManager.ADJUST_RAISE
            } else {
                AudioManager.ADJUST_LOWER
            }
            // One adjustment per step, capped: "louder" is one step, and a
            // misheard "a hundred steps louder" must not slam the stream to
            // maximum in a loop.
            val count = if (steps < 0) -steps else steps
            val bounded = if (count > 10) 10 else count
            for (i in 0 until bounded) {
                am.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, 0)
            }
            true
        } catch (e: SecurityException) {
            false
        } catch (e: Exception) {
            false
        }
    }

    private fun setMuted(muted: Boolean): Boolean {
        val am = audioManager() ?: return false
        return try {
            am.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                if (muted) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE,
                0
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun isMuted(): Boolean? {
        val am = audioManager() ?: return null
        return try {
            am.isStreamMute(AudioManager.STREAM_MUSIC)
        } catch (e: Exception) {
            null
        }
    }

    // -- Apps -----------------------------------------------------------------

    private fun normalize(value: String): String =
        value.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9]"), "")

    /**
     * Opens the launcher app whose name best matches what was said.
     *
     * Matching, in order: exact name, name starts with the phrase, name
     * contains the phrase. First hit at the highest tier wins; ties go to the
     * shorter label, which is why "open chrome" beats "Chrome Beta". A null
     * result means nothing matched and the Flutter side says so out loud.
     */
    private fun openApp(spokenName: String?, result: MethodChannel.Result) {
        if (spokenName.isNullOrBlank()) {
            result.success(null)
            return
        }
        val query = normalize(spokenName)
        if (query.isEmpty) {
            result.success(null)
            return
        }

        val pm = context.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val activities: List<ResolveInfo> = try {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(launcherIntent, 0)
        } catch (e: Exception) {
            emptyList()
        }

        var best: ResolveInfo? = null
        var bestScore = 0
        var bestLabel = ""
        for (info in activities) {
            val label = try {
                info.loadLabel(pm).toString()
            } catch (e: Exception) {
                continue
            }
            val normalizedLabel = normalize(label)
            if (normalizedLabel.isEmpty()) continue
            val score = when {
                normalizedLabel == query -> 100
                normalizedLabel.startsWith(query) -> 80 - (normalizedLabel.length - query.length).coerceAtLeast(0)
                normalizedLabel.contains(query) -> 60
                else -> 0
            }
            val shorter = normalizedLabel.length < bestLabel.length
            if (score > bestScore || (score == bestScore && best != null && shorter)) {
                bestScore = score
                best = info
                bestLabel = label
            }
        }

        val match = best
        if (match == null || match.activityInfo == null) {
            result.success(null)
            return
        }

        val launch = pm.getLaunchIntentForPackage(match.activityInfo.packageName)
        if (launch == null) {
            // Found it, but it cannot be started from here (no launcher
            // activity, or the package was disabled between the query and the
            // launch). Distinct from "no such app" on purpose.
            result.error("launch_failed", bestLabel, null)
            return
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(launch)
            result.success(bestLabel)
        } catch (e: ActivityNotFoundException) {
            result.error("launch_failed", bestLabel, e.message)
        } catch (e: SecurityException) {
            result.error("launch_failed", bestLabel, e.message)
        }
    }

    // -- Clock ----------------------------------------------------------------

    private fun startTimer(seconds: Int): Boolean {
        if (seconds <= 0) return false
        val pm = context.packageManager
        val intent = Intent(AlarmClock.ACTION_SET_TIMER)
            .putExtra(AlarmClock.EXTRA_LENGTH, seconds)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startQuietly(pm, intent)
    }

    private fun setAlarm(hour: Int, minute: Int): Boolean {
        val pm = context.packageManager
        // EXTRA_SKIP_UI only takes effect with SET_ALARM granted; without it the
        // clock app shows its own confirmation, which is the correct behaviour
        // for an alarm somebody else's model parsed.
        val canSkipUi = context.checkSelfPermission(ALARM_PERMISSION) ==
            PackageManager.PERMISSION_GRANTED
        val intent = Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour)
            .putExtra(AlarmClock.EXTRA_MINUTES, minute)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, canSkipUi)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return startQuietly(pm, intent)
    }

    private fun startQuietly(pm: PackageManager, intent: Intent): Boolean {
        val resolved = try {
            @Suppress("DEPRECATION")
            intent.resolveActivity(pm)
        } catch (e: Exception) {
            null
        }
        if (resolved == null) return false
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }
    }

    // -- Speech ---------------------------------------------------------------

    private fun ensureTts() {
        if (tts != null) return
        tts = TextToSpeech(context) { status ->
            ttsReady = status == TextToSpeech.SUCCESS
            if (ttsReady) {
                try {
                    tts?.language = Locale.getDefault()
                } catch (e: Exception) {
                    // A missing language pack still speaks English; the answer
                    // being read in the wrong accent beats not being read.
                }
                val queued = pendingUtterance
                pendingUtterance = null
                if (queued != null) speakNow(queued)
            }
        }
        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {}
            override fun onError(utteranceId: String?) {}
        })
    }

    private fun speak(text: String?): Boolean {
        if (text.isNullOrBlank()) return false
        ensureTts()
        if (!ttsReady) {
            // The engine takes a moment to bind. Rather than answering false
            // (which reads as "Puck cannot speak") or losing the sentence, hold
            // the most recent one and say it when the engine is up.
            pendingUtterance = text
            return true
        }
        return speakNow(text)
    }

    private fun speakNow(text: String): Boolean {
        val engine = tts ?: return false
        return try {
            val mode = Bundle()
            val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, mode, "puck")
            code == TextToSpeech.SUCCESS
        } catch (e: Exception) {
            false
        }
    }

    private fun stopSpeaking() {
        pendingUtterance = null
        try {
            tts?.stop()
        } catch (e: Exception) {
            // Already stopped, or the engine died. Either way, silence.
        }
    }

    // -- PCM playback ---------------------------------------------------------

    private fun playPcm(samples: FloatArray?, sampleRate: Int?): Boolean {
        if (samples == null || samples.isEmpty()) return false
        val rate = sampleRate ?: 22050
        val generation = ++playbackGeneration
        releaseTrack()
        audioExecutor.execute { playBlocking(samples, rate, generation) }
        return true
    }

    private fun playBlocking(samples: FloatArray, sampleRate: Int, generation: Int) {
        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_FLOAT
        )
        val bufferSize = if (minBuffer > 0) minBuffer * 2 else 8192

        var track: AudioTrack? = null
        try {
            track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(bufferSize)
                .build()

            activeTrack = track
            track.play()

            var offset = 0
            while (offset < samples.size) {
                if (generation != playbackGeneration) break
                val written = track.write(samples, offset, samples.size - offset, AudioTrack.WRITE_BLOCKING)
                if (written <= 0) break
                offset += written
            }

            if (generation == playbackGeneration) {
                try {
                    track.stop()
                } catch (e: Exception) {
                    // Already stopped.
                }
            }
        } catch (e: Exception) {
            // No audio output available (a call is in progress, or the device
            // has no free output). The card is still on screen.
        } finally {
            if (generation == playbackGeneration) {
                try {
                    track?.release()
                } catch (e: Exception) {
                    // Nothing to release.
                }
                activeTrack = null
            }
        }
    }

    private fun stopPlayback() {
        playbackGeneration++
        releaseTrack()
    }

    private fun releaseTrack() {
        val track = activeTrack ?: return
        activeTrack = null
        try {
            track.pause()
            track.flush()
            track.stop()
        } catch (e: Exception) {
            // Already stopped or never started.
        }
        try {
            track.release()
        } catch (e: Exception) {
            // Already released.
        }
    }

    /** Called when the activity goes away: nothing here should outlive it. */
    fun dispose() {
        stopSpeaking()
        stopPlayback()
        try {
            tts?.shutdown()
        } catch (e: Exception) {
            // Engine already gone.
        }
        tts = null
        ttsReady = false
        audioExecutor.shutdownNow()
    }

    companion object {
        const val CHANNEL = "com.rolexsir.puck/platform"
        private const val ALARM_PERMISSION = "com.android.alarm.permission.SET_ALARM"
    }
}
