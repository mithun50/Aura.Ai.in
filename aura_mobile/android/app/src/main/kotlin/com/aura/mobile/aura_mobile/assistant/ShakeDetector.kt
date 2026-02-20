package com.aura.mobile.aura_mobile.assistant

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.sqrt

class ShakeDetector(context: Context, private val onShake: () -> Unit) : SensorEventListener {

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer: Sensor? = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    
    // threshold logic: If acceleration > threshold (12 m/s^2)
    private val SHAKE_THRESHOLD_GRAVITY = 12.0f
    private val SHAKE_COOLDOWN_MS = 3000L
    private val MIN_TIME_BETWEEN_SHAKES_MS = 500L
    
    private var lastShakeTime: Long = 0
    private var lastTriggerTime: Long = 0
    private var shakeCount = 0

    fun start() {
        accelerometer?.let {
            sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return

        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]

        val gX = x / SensorManager.GRAVITY_EARTH
        val gY = y / SensorManager.GRAVITY_EARTH
        val gZ = z / SensorManager.GRAVITY_EARTH

        // gForce will be close to 1 when there is no movement.
        val gForce = sqrt((gX * gX + gY * gY + gZ * gZ).toDouble()).toFloat()

        if (gForce > SHAKE_THRESHOLD_GRAVITY / SensorManager.GRAVITY_EARTH) {
            val now = System.currentTimeMillis()
            
            // Ignore shake within cooldown (3 seconds)
            if (now - lastTriggerTime < SHAKE_COOLDOWN_MS) {
                return
            }

            // check repeated within 500ms
            if (lastShakeTime + MIN_TIME_BETWEEN_SHAKES_MS > now) {
                shakeCount++
            } else {
                shakeCount = 1
            }
            
            lastShakeTime = now

            if (shakeCount >= 2) {
                lastTriggerTime = now
                shakeCount = 0
                onShake()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
}
