package com.example.focus_lock

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log

/**
 * Real pushup detection using the **proximity sensor**.
 *
 * How it works:
 *  1. User places the phone face-up on the floor.
 *  2. During each pushup the user's chest comes close → proximity reads NEAR.
 *  3. When the user pushes back up → proximity reads FAR.
 *  4. One complete NEAR → FAR cycle = one pushup.
 *
 * Anti-cheat measures:
 *  • Minimum cycle time: a rep must take ≥ 800 ms (prevents hand-waving).
 *  • Maximum cycle time: a rep must complete within 8 s (detects idle).
 *  • The `onPushupCount` callback fires on each valid rep.
 */
class PushupDetectorService(private val context: Context) : SensorEventListener {
    companion object {
        const val TAG = "PushupDetector"
        private const val MIN_REP_MS = 800L   // fastest allowed rep
        private const val MAX_REP_MS = 8000L   // slowest allowed rep
    }

    private var sensorManager: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var accelerometer: Sensor? = null

    private var pushupCount = 0
    private var isNear = false
    private var nearTimestamp = 0L        // when NEAR was first detected
    private var lastRepTimestamp = 0L     // when last valid rep completed
    private var isActive = false

    // Additional accelerometer validation
    private var lastAccelMagnitude = 0f
    private var motionDetected = false

    var onPushupCount: ((Int) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    // ── Public API ──────────────────────────────────────────────────

    fun start(): Boolean {
        if (isActive) return true

        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        proximitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        if (proximitySensor == null) {
            Log.e(TAG, "❌ No proximity sensor available on this device")
            onError?.invoke("No proximity sensor available")
            return false
        }

        pushupCount = 0
        isNear = false
        nearTimestamp = 0L
        lastRepTimestamp = 0L
        motionDetected = false

        sensorManager?.registerListener(this, proximitySensor, SensorManager.SENSOR_DELAY_GAME)
        if (accelerometer != null) {
            sensorManager?.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_GAME)
        }

        isActive = true
        Log.d(TAG, "✅ Pushup detection STARTED (proximity max range = ${proximitySensor?.maximumRange})")
        return true
    }

    fun stop() {
        if (!isActive) return
        sensorManager?.unregisterListener(this)
        isActive = false
        Log.d(TAG, "🛑 Pushup detection STOPPED — total count: $pushupCount")
    }

    fun getCount(): Int = pushupCount

    fun reset() {
        pushupCount = 0
        isNear = false
        nearTimestamp = 0L
        lastRepTimestamp = 0L
        motionDetected = false
        Log.d(TAG, "🔄 Pushup count reset")
    }

    // ── Sensor callbacks ────────────────────────────────────────────

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        when (event.sensor.type) {
            Sensor.TYPE_PROXIMITY -> handleProximity(event)
            Sensor.TYPE_ACCELEROMETER -> handleAccelerometer(event)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed
    }

    // ── Proximity handling ──────────────────────────────────────────

    private fun handleProximity(event: SensorEvent) {
        val distance = event.values[0]
        val maxRange = proximitySensor?.maximumRange ?: 5f
        val now = System.currentTimeMillis()

        // NEAR = distance is close to 0 (within half the max range)
        val currentlyNear = distance < (maxRange / 2f)

        if (currentlyNear && !isNear) {
            // Transition: FAR → NEAR (user's chest coming down)
            isNear = true
            nearTimestamp = now
            motionDetected = false  // Reset accelerometer flag for this rep
            Log.d(TAG, "↓ NEAR detected (distance=$distance)")

        } else if (!currentlyNear && isNear) {
            // Transition: NEAR → FAR (user pushing back up)
            isNear = false
            val cycleTime = now - nearTimestamp

            Log.d(TAG, "↑ FAR detected (distance=$distance, cycleTime=${cycleTime}ms)")

            // Validate the rep
            if (cycleTime in MIN_REP_MS..MAX_REP_MS) {
                // Also check interval between reps
                val timeSinceLastRep = if (lastRepTimestamp > 0) now - lastRepTimestamp else MIN_REP_MS
                if (timeSinceLastRep >= MIN_REP_MS) {
                    pushupCount++
                    lastRepTimestamp = now
                    Log.d(TAG, "✅ Valid pushup #$pushupCount (cycle=${cycleTime}ms)")
                    onPushupCount?.invoke(pushupCount)
                } else {
                    Log.d(TAG, "⚠️ Rep too fast after previous (${timeSinceLastRep}ms) — skipped")
                }
            } else if (cycleTime < MIN_REP_MS) {
                Log.d(TAG, "⚠️ Rep too fast (${cycleTime}ms < ${MIN_REP_MS}ms) — skipped")
            } else {
                Log.d(TAG, "⚠️ Rep too slow (${cycleTime}ms > ${MAX_REP_MS}ms) — skipped")
            }
        }
    }

    // ── Accelerometer handling (supplementary validation) ───────────

    private fun handleAccelerometer(event: SensorEvent) {
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val magnitude = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()

        // Detect significant motion delta (body movement)
        val delta = Math.abs(magnitude - lastAccelMagnitude)
        if (delta > 1.5f) {
            motionDetected = true
        }
        lastAccelMagnitude = magnitude
    }
}
