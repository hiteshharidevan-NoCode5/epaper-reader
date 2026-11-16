package com.example.epaper_reader

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val ch = "epaper_reader/intent"
    private var pending: Intent? = null

    override fun onCreate(s: Bundle?) { super.onCreate(s); pending = intent }

    override fun onNewIntent(i: Intent) {
        super.onNewIntent(i); setIntent(i)
        flutterEngine?.dartExecutor?.binaryMessenger?.let { m ->
            extract(i)?.let { MethodChannel(m, ch).invokeMethod("onNewPdf", it) }
        }
    }

    override fun configureFlutterEngine(fe: FlutterEngine) {
        super.configureFlutterEngine(fe)
        MethodChannel(fe.dartExecutor.binaryMessenger, ch).setMethodCallHandler { c, r ->
            if (c.method == "getInitialPdf") { r.success(pending?.let { extract(it) }); pending = null }
            else r.notImplemented()
        }
    }

    private fun extract(i: Intent): Map<String, Any>? {
        val u: Uri = i.data ?: return null
        return try {
            val b = contentResolver.openInputStream(u)?.use { it.readBytes() } ?: return null
            var t = "NuzEPpr"
            contentResolver.query(u, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx != -1 && c.moveToFirst()) t = c.getString(idx) ?: t
            }
            mapOf("bytes" to b, "title" to t)
        } catch (e: Exception) { null }
    }
}
