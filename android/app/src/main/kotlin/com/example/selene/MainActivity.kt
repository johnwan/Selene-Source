package org.moontechlab.selene

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    private var tvDiscovery: TvDiscovery? = null
    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        tvDiscovery = TvDiscovery(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun cleanUpFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        tvDiscovery?.dispose(); tvDiscovery = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
