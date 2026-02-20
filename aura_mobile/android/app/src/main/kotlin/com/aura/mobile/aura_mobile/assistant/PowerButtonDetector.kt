package com.aura.mobile.aura_mobile.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Detects a double-press of the power button by monitoring SCREEN_ON / SCREEN_OFF broadcasts.
 *
 * Pattern:
 *  1st press (screen was ON)  → ACTION_SCREEN_OFF  (t0)
 *  2nd press (within 650ms)   → ACTION_SCREEN_ON   (t1)
 *  If (t1 - t0) ≤ DOUBLE_PRESS_WINDOW_MS  →  double-press detected ✓
 *
 * Works reliably on all OEM Android variants without root or accessibility services.
 */
class PowerButtonDetector(
    private val onDoublePress: () -> Unit
) : BroadcastReceiver() {

    companion object {
        private const val DOUBLE_PRESS_WINDOW_MS = 650L
        private const val TAG = "PowerButtonDetector"
    }

    // Time of the last SCREEN_OFF event
    private var lastScreenOffTime = 0L

    override fun onReceive(context: Context?, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SCREEN_OFF -> {
                lastScreenOffTime = System.currentTimeMillis()
                Log.d(TAG, "Screen OFF (t=$lastScreenOffTime)")
            }
            Intent.ACTION_SCREEN_ON -> {
                val now = System.currentTimeMillis()
                val delta = now - lastScreenOffTime
                Log.d(TAG, "Screen ON  (delta=${delta}ms)")
                if (lastScreenOffTime > 0 && delta <= DOUBLE_PRESS_WINDOW_MS) {
                    Log.d(TAG, "Double power-button press detected! Triggering assistant.")
                    lastScreenOffTime = 0L // reset so it doesn't fire again immediately
                    onDoublePress()
                }
            }
        }
    }
}
