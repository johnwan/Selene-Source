package org.moontechlab.selene

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

class TvDiscovery(context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val main = Handler(Looper.getMainLooper())
    private val store = TvPrivateStore(context)
    private val methods = MethodChannel(messenger, "org.moontechlab.selene/tv")
    private val events = EventChannel(messenger, "org.moontechlab.selene/tv_devices")
    private var sink: EventChannel.EventSink? = null
    private var listener: NsdManager.DiscoveryListener? = null
    private val devices = mutableMapOf<String, Map<String, Any>>()
    private val present = mutableSetOf<String>()
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var generation = 0
    init {
        events.setStreamHandler(this)
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> { start(); result.success(null) }
                    "stop" -> { stop(); result.success(null) }
                    "read" -> result.success(store.read())
                    "write" -> { store.write(call.arguments as Map<*, *>); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("tv_unavailable", "TV connection unavailable", null) }
        }
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink; publish() }
    override fun onCancel(arguments: Any?) { sink = null; stop() }
    private fun publish() { sink?.success(devices.values.distinctBy { it["id"] }.toList()) }
    private fun start() {
        if (listener != null) return
        val current = ++generation
        val callback = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, code: Int) { main.post { if (current == generation) { listener = null; sink?.error("discovery_failed", "Unable to discover TVs", null) } } }
            override fun onStopDiscoveryFailed(type: String, code: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) { main.post {
                if (current == generation) { present.add(info.serviceName); queue.addLast(info); resolveNext(current) }
            } }
            override fun onServiceLost(info: NsdServiceInfo) { main.post {
                if (current == generation) { present.remove(info.serviceName); devices.remove(info.serviceName); publish() }
            } }
        }
        listener = callback
        try { manager.discoverServices("_selene-tv._tcp.", NsdManager.PROTOCOL_DNS_SD, callback) }
        catch (e: Exception) { listener = null; throw e }
    }
    @Suppress("DEPRECATION") private fun resolveNext(current: Int) {
        if (resolving || queue.isEmpty() || current != generation) return
        val info = queue.removeFirst(); resolving = true
        manager.resolveService(info, object : NsdManager.ResolveListener {
            override fun onResolveFailed(service: NsdServiceInfo, code: Int) { finish(null) }
            override fun onServiceResolved(service: NsdServiceInfo) { finish(service) }
            private fun finish(service: NsdServiceInfo?) { main.post {
                if (current != generation) return@post
                resolving = false
                if (service != null && info.serviceName in present) {
                    fun attribute(name: String) = service.attributes[name]?.toString(Charsets.UTF_8)
                    val id = attribute("id"); val host = service.host?.hostAddress
                    if (!id.isNullOrBlank() && !host.isNullOrBlank() && service.port in 1..65535) {
                        devices[info.serviceName] = mapOf("id" to id, "name" to (attribute("name") ?: service.serviceName), "host" to host, "port" to service.port, "version" to (attribute("version")?.toIntOrNull() ?: 0))
                        publish()
                    }
                }
                resolveNext(current)
            } }
        })
    }
    private fun stop() {
        ++generation
        listener?.let { runCatching { manager.stopServiceDiscovery(it) } }; listener = null
        queue.clear(); present.clear(); devices.clear(); resolving = false; publish()
    }
    fun dispose() { stop(); methods.setMethodCallHandler(null); events.setStreamHandler(null); sink = null }
}
