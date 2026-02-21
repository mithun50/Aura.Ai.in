package com.aura.mobile.aura_mobile.assistant

import android.animation.ObjectAnimator
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * OverlayManager draws a floating overlay using WindowManager.addView().
 * This works correctly from a Background Service with SYSTEM_ALERT_WINDOW permission,
 * avoiding Android 10+ BAL_BLOCK restrictions on startActivity().
 */
class OverlayManager(private val context: Context) {

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: View? = null
    private var windowParams: WindowManager.LayoutParams? = null
    private val handler = Handler(Looper.getMainLooper())
    private val activeAnimators = mutableListOf<ObjectAnimator>()
    private var isShowing = false
    private var isTouchable = false

    // Floating mic bubble
    private var bubbleView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var removeRunnable: Runnable? = null

    fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else true
    }

    fun showOverlay(state: String) {
        if (!canDrawOverlays()) {
            Log.e("OverlayManager", "Cannot draw overlays - permission not granted")
            return
        }
        handler.post {
            removeRunnable?.let { handler.removeCallbacks(it) }
            if (overlayView == null) {
                createAndAddOverlayView()
            }
            // Always ensure the overlay is touchable when shown
            setTouchable(true)
            updateState(state)
        }
    }

    fun updateState(state: String) {
        handler.post {
            if (overlayView == null) return@post
            val statusText: TextView? = overlayView!!.findViewWithTag("status_text")
            val orbView: View? = overlayView!!.findViewWithTag("orb_view")

            when (state) {
                "LISTENING" -> {
                    statusText?.text = "Hi there, I'm listening..."
                    showOverlayPanel()
                    startPulseAnimation(orbView)
                }
                "PROCESSING" -> {
                    statusText?.text = "Thinking about that..."
                    showOverlayPanel()
                    startSpinAnimation(orbView)
                }
                "SPEAKING" -> {
                    statusText?.text = "Here's what I found..."
                    showOverlayPanel()
                    startPulseAnimation(orbView)
                }
                "IDLE" -> {
                    hideOverlay()
                }
            }
        }
    }

    fun hideOverlay() {
        handler.post {
            if (overlayView == null) return@post
            
            // Immediately let touches pass through to the app underneath
            setTouchable(false)

            // Animate out before removing
            val panel: View? = overlayView?.findViewWithTag("panel")
            val dimBg: View? = overlayView?.findViewWithTag("dim_bg")

            stopAnimations()
            val duration = 300L
            
            panel?.let {
                ObjectAnimator.ofFloat(it, "translationY", it.translationY, dpToPx(320).toFloat())
                    .apply { this.duration = duration; start() }
            }
            dimBg?.let {
                ObjectAnimator.ofFloat(it, "alpha", it.alpha, 0f).apply { this.duration = duration; start() }
            }

            // Delay removal until animation completes
            removeRunnable?.let { handler.removeCallbacks(it) }
            removeRunnable = Runnable {
                try {
                    overlayView?.let { windowManager.removeViewImmediate(it) }
                } catch (e: Exception) {
                    Log.e("OverlayManager", "Error removing overlay: ${e.message}")
                }
                overlayView = null
                isShowing = false
            }
            handler.postDelayed(removeRunnable!!, duration + 50)
        }
    }

    /**
     * Show a small draggable floating mic bubble on the right edge of the screen.
     * Tapping it calls [onTap] to trigger the assistant.
     */
    fun showFloatingBubble(onTap: () -> Unit) {
        if (!canDrawOverlays()) return
        handler.post {
            if (bubbleView != null) return@post // already showing

            val size = dpToPx(56)
            val params = WindowManager.LayoutParams(
                size, size,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.END
                x = dpToPx(8)
                y = dpToPx(200)
            }
            bubbleParams = params

            // Build the bubble view
            val bubble = FrameLayout(context)
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                colors = intArrayOf(Color.parseColor("#2b5876"), Color.parseColor("#4e4376")) // sleek purple/blue gradient
                setStroke(dpToPx(2), Color.argb(80, 255, 255, 255))
            }
            bubble.background = bg

            val micLabel = TextView(context).apply {
                text = "🎤"
                textSize = 22f
                gravity = Gravity.CENTER
            }
            bubble.addView(micLabel, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))

            // Drag + tap logic
            var dragStartX = 0f
            var dragStartY = 0f
            var startParamsX = 0
            var startParamsY = 0
            var isDragging = false

            bubble.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        dragStartX = event.rawX
                        dragStartY = event.rawY
                        startParamsX = params.x
                        startParamsY = params.y
                        isDragging = false
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - dragStartX
                        val dy = event.rawY - dragStartY
                        if (Math.abs(dx) > 8 || Math.abs(dy) > 8) isDragging = true
                        if (isDragging) {
                            params.x = (startParamsX - dx).toInt().coerceAtLeast(0)
                            params.y = (startParamsY + dy).toInt().coerceAtLeast(0)
                            try { windowManager.updateViewLayout(bubble, params) } catch (e: Exception) { }
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            // It's a tap — pulse animation + trigger
                            ObjectAnimator.ofFloat(bubble, "scaleX", 1f, 1.25f, 1f)
                                .apply { duration = 200; start() }
                            ObjectAnimator.ofFloat(bubble, "scaleY", 1f, 1.25f, 1f)
                                .apply { duration = 200; start() }
                            handler.postDelayed({ onTap() }, 100)
                        }
                        true
                    }
                    else -> false
                }
            }

            bubbleView = bubble
            try {
                windowManager.addView(bubble, params)
                Log.d("OverlayManager", "Floating bubble shown")
            } catch (e: Exception) {
                Log.e("OverlayManager", "Failed to show bubble: ${e.message}")
                bubbleView = null
            }
        }
    }

    fun hideFloatingBubble() {
        handler.post {
            try {
                bubbleView?.let { windowManager.removeView(it) }
            } catch (e: Exception) { }
            bubbleView = null
        }
    }

    private fun createAndAddOverlayView() {
        windowParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM
        }

        val params = windowParams!!

        val rootFrame = object : FrameLayout(context) {
            override fun dispatchKeyEvent(event: android.view.KeyEvent?): Boolean {
                if (event?.keyCode == android.view.KeyEvent.KEYCODE_BACK && event.action == android.view.KeyEvent.ACTION_UP) {
                    hideOverlay()
                    val cancelIntent = android.content.Intent("com.aura.mobile.assistant.CANCEL")
                    cancelIntent.setPackage(context.packageName)
                    context.sendBroadcast(cancelIntent)
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }
        rootFrame.setBackgroundColor(Color.TRANSPARENT)

        // Full-screen dim overlay
        val dimBackground = View(context)
        dimBackground.setBackgroundColor(Color.argb(100, 0, 0, 0))
        dimBackground.alpha = 0f
        dimBackground.tag = "dim_bg"
        dimBackground.setOnClickListener {
            // Dismiss assistant when tapping outside the panel
            hideOverlay()
            val cancelIntent = android.content.Intent("com.aura.mobile.assistant.CANCEL")
            cancelIntent.setPackage(context.packageName)
            context.sendBroadcast(cancelIntent)
        }
        rootFrame.addView(dimBackground, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Sliding panel
        val panelLayout = FrameLayout(context)
        panelLayout.tag = "panel"
        panelLayout.translationY = dpToPx(320).toFloat()

        val innerPanel = FrameLayout(context)
        innerPanel.tag = "inner_panel"
        
        // Modern rounded top background
        val panelBg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(Color.parseColor("#1E1E24")) // sleek dark background
            cornerRadii = floatArrayOf(
                dpToPx(24).toFloat(), dpToPx(24).toFloat(), // top left
                dpToPx(24).toFloat(), dpToPx(24).toFloat(), // top right
                0f, 0f, // bottom right
                0f, 0f  // bottom left
            )
        }
        innerPanel.background = panelBg
        innerPanel.elevation = dpToPx(16).toFloat()
        
        // Sleek Drag Handle Indicator
        val dragHandle = View(context).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(4).toFloat()
                setColor(Color.parseColor("#50505A"))
            }
        }
        val handleParams = FrameLayout.LayoutParams(dpToPx(36), dpToPx(4)).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            setMargins(0, dpToPx(12), 0, 0)
        }
        innerPanel.addView(dragHandle, handleParams)

        val statusTextView = TextView(context)
        statusTextView.text = "Hi there, I'm listening..."
        statusTextView.setTextColor(Color.parseColor("#E0E0E0"))
        statusTextView.textSize = 24f
        statusTextView.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL))
        statusTextView.gravity = Gravity.CENTER
        statusTextView.tag = "status_text"
        statusTextView.setPadding(40, dpToPx(32), 40, dpToPx(16))
        val statusParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        )
        statusParams.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        innerPanel.addView(statusTextView, statusParams)

        // Orb
        val orbSize = dpToPx(100)
        val orbView = View(context)
        orbView.tag = "orb_view"
        orbView.background = createOrbDrawable()
        val orbContainerParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            dpToPx(200)
        )
        orbContainerParams.gravity = Gravity.CENTER
        val orbContainer = FrameLayout(context)
        orbContainer.tag = "orb_container"
        val orbParams = FrameLayout.LayoutParams(orbSize, orbSize)
        orbParams.gravity = Gravity.CENTER
        orbContainer.addView(orbView, orbParams)
        innerPanel.addView(orbContainer, orbContainerParams)

        panelLayout.addView(innerPanel, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        val panelParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            dpToPx(320)
        )
        panelParams.gravity = Gravity.BOTTOM
        rootFrame.addView(panelLayout, panelParams)

        overlayView = rootFrame
        try {
            windowManager.addView(rootFrame, params)
            Log.d("OverlayManager", "Overlay view added to WindowManager successfully")
        } catch (e: Exception) {
            Log.e("OverlayManager", "Failed to add overlay: ${e.message}")
            overlayView = null
        }
    }

    /**
     * Show a contact disambiguation picker inside the overlay.
     * Creates tappable buttons for each matching contact, calls [onSelected] when tapped.
     */
    fun showContactPicker(
        contacts: List<DeviceControlService.ContactMatch>,
        onSelected: (DeviceControlService.ContactMatch) -> Unit
    ) {
        handler.post {
            if (!canDrawOverlays()) return@post
            if (overlayView == null) createAndAddOverlayView()

            // Enable touches on the overlay window
            setTouchable(true)

            val statusText: TextView? = overlayView!!.findViewWithTag("status_text")
            val orbContainer: View? = overlayView!!.findViewWithTag("orb_container")
            val innerPanel: FrameLayout? = overlayView!!.findViewWithTag("inner_panel")

            statusText?.text = "Who do you want to call?"

            // Hide orb, show contact list
            orbContainer?.visibility = View.GONE

            // Remove any existing contact list
            val existingList: View? = overlayView!!.findViewWithTag("contact_list")
            (existingList?.parent as? ViewGroup)?.removeView(existingList)

            val scrollView = ScrollView(context).apply { tag = "contact_list" }
            val listLayout = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dpToPx(16), dpToPx(8), dpToPx(16), dpToPx(24))
            }

            contacts.forEachIndexed { index, contact ->
                val btn = TextView(context).apply {
                    text = "${index + 1}. ${contact.displayName}\n${contact.number}"
                    setTextColor(Color.WHITE)
                    textSize = 16f
                    typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.CENTER
                    setPadding(dpToPx(20), dpToPx(16), dpToPx(20), dpToPx(16))
                    background = createContactButtonBackground()
                    setOnClickListener {
                        setTouchable(false)
                        orbContainer?.visibility = View.VISIBLE
                        val contactList: View? = overlayView?.findViewWithTag("contact_list")
                        (contactList?.parent as? ViewGroup)?.removeView(contactList)
                        updateState("IDLE")
                        onSelected(contact)
                    }
                }
                val btnParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply { setMargins(0, 0, 0, dpToPx(10)) }
                listLayout.addView(btn, btnParams)
            }

            scrollView.addView(listLayout)
            val scrollParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dpToPx(220)
            ).apply { gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL }

            innerPanel?.addView(scrollView, scrollParams)
            showOverlayPanel()
        }
    }

    private fun setTouchable(enabled: Boolean) {
        if (isTouchable == enabled) return
        isTouchable = enabled
        val params = windowParams ?: return
        val root = overlayView ?: return
        if (enabled) {
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
        } else {
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        try { windowManager.updateViewLayout(root, params) } catch (e: Exception) { }
    }

    private fun createContactButtonBackground(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(16).toFloat()
            setColor(Color.parseColor("#2A2A35")) // slightly lighter than bg
            setStroke(dpToPx(1), Color.parseColor("#4facfe")) // subtle blue border
        }
    }

    private var panelAnimator: ObjectAnimator? = null
    private var dimAnimator: ObjectAnimator? = null

    private fun showOverlayPanel() {
        if (isShowing) return
        isShowing = true
        val panel: View = overlayView?.findViewWithTag("panel") ?: return
        val dimBg: View? = overlayView?.findViewWithTag("dim_bg")

        panelAnimator?.cancel()
        dimAnimator?.cancel()

        panelAnimator = ObjectAnimator.ofFloat(panel, "translationY", panel.translationY, 0f)
            .apply { duration = 400; interpolator = android.view.animation.DecelerateInterpolator(); start() }
        
        dimBg?.let {
            dimAnimator = ObjectAnimator.ofFloat(it, "alpha", it.alpha, 1f)
                .apply { duration = 400; start() }
        }
    }

    private fun hideOverlayPanel() {
        if (!isShowing) return
        isShowing = false
        val panel: View = overlayView?.findViewWithTag("panel") ?: return
        val dimBg: View? = overlayView?.findViewWithTag("dim_bg")

        panelAnimator?.cancel()
        dimAnimator?.cancel()

        panelAnimator = ObjectAnimator.ofFloat(panel, "translationY", panel.translationY, dpToPx(320).toFloat())
            .apply { duration = 300; interpolator = android.view.animation.AccelerateInterpolator(); start() }
            
        dimBg?.let {
            dimAnimator = ObjectAnimator.ofFloat(it, "alpha", it.alpha, 0f)
                .apply { duration = 300; start() }
        }
    }

    private fun startPulseAnimation(view: View?) {
        view ?: return
        stopAnimations()

        val alphaAnim = ObjectAnimator.ofFloat(view, "alpha", 0.6f, 1.0f).apply {
            duration = 1000
            repeatCount = ObjectAnimator.INFINITE
            repeatMode = ObjectAnimator.REVERSE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
        }
        val scaleXAnim = ObjectAnimator.ofFloat(view, "scaleX", 1.0f, 1.15f).apply {
            duration = 1000
            repeatCount = ObjectAnimator.INFINITE
            repeatMode = ObjectAnimator.REVERSE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
        }
        val scaleYAnim = ObjectAnimator.ofFloat(view, "scaleY", 1.0f, 1.15f).apply {
            duration = 1000
            repeatCount = ObjectAnimator.INFINITE
            repeatMode = ObjectAnimator.REVERSE
            interpolator = android.view.animation.AccelerateDecelerateInterpolator()
        }
        activeAnimators.addAll(listOf(alphaAnim, scaleXAnim, scaleYAnim))
        activeAnimators.forEach { it.start() }
    }

    private fun startSpinAnimation(view: View?) {
        view ?: return
        stopAnimations()

        val spinAnim = ObjectAnimator.ofFloat(view, "rotation", 0f, 360f).apply {
            duration = 1200
            repeatCount = ObjectAnimator.INFINITE
            repeatMode = ObjectAnimator.RESTART
        }
        activeAnimators.add(spinAnim)
        spinAnim.start()
    }

    private fun stopAnimations() {
        activeAnimators.forEach { it.cancel() }
        activeAnimators.clear()
        overlayView?.findViewWithTag<View>("orb_view")?.apply {
            scaleX = 1f; scaleY = 1f; alpha = 1f; rotation = 0f
        }
    }

    private fun createOrbDrawable(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            gradientType = GradientDrawable.RADIAL_GRADIENT
            colors = intArrayOf(
                Color.parseColor("#4facfe"), // vibrant blue center
                Color.parseColor("#00f2fe"), // cyan outer
                Color.TRANSPARENT
            )
            setGradientRadius(dpToPx(60).toFloat()) // Slightly larger blur radius
        }
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * context.resources.displayMetrics.density).toInt()
    }
}
