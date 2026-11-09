// Copyright (c) 2026 VitruvianSoftware

package dev.vitruvian.wand.core

/**
 * JNI declarations for `libwand_jni.so` (`apps/suites/wand/android/jni`).
 *
 * All functions operate on an opaque native handle (`Long`, backed by `Box<Mutex<Option<Bridge>>>`
 * in Rust) and never throw or unwind across the JNI boundary.
 */
object WandNative {
  const val PLATFORM_DESKTOP: Int = 0
  const val PLATFORM_ANDROID: Int = 1
  const val PLATFORM_ANDROID_TV: Int = 2

  val isLoaded: Boolean =
      try {
        System.loadLibrary("wand_jni")
        true
      } catch (e: UnsatisfiedLinkError) {
        Log.w("Wand", "Failed to load libwand_jni.so", e)
        false
      }

  @JvmStatic external fun nativeCreate(platform: Int, configJson: String): Long

  @JvmStatic external fun nativeDestroy(handle: Long)

  @JvmStatic external fun nativeDefaultConfig(platform: Int): String

  @JvmStatic external fun nativeFeed(handle: Long, packet: ByteArray, timestampUs: Long): String

  @JvmStatic external fun nativeTick(handle: Long, timestampUs: Long): String

  @JvmStatic external fun nativeReleaseAll(handle: Long): String

  @JvmStatic external fun nativeSetConfig(handle: Long, configJson: String): String

  @JvmStatic external fun nativeGetConfig(handle: Long): String

  @JvmStatic external fun nativeSetTestMode(handle: Long, enabled: Boolean)

  @JvmStatic external fun nativeRecalibrate(handle: Long)

  @JvmStatic external fun nativeLastSample(handle: Long): String

  @JvmStatic external fun nativeBatteryLow(level: Int): Boolean
}
