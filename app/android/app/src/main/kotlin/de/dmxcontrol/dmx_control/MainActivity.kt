package de.dmxcontrol.dmx_control

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    // Zuletzt gesehenes WLAN und ob Dart gerade Internet braucht (Download)
    private var wifi: Network? = null
    private var internetMode = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dmx_control/network")
        // Dart → Android: für Downloads die WLAN-Bindung kurz lösen. Ohne Bindung
        // nimmt Android das Netz mit Internet (Heim-WLAN oder mobile Daten).
        // Bestehende Sockets (Art-Net) bleiben an ihrem Netz.
        ch.setMethodCallHandler { call, result ->
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            when (call.method) {
                "useInternet" -> {
                    internetMode = true
                    cm.bindProcessToNetwork(null)
                    result.success(null)
                }
                "useWifi" -> {
                    internetMode = false
                    wifi?.let { cm.bindProcessToNetwork(it) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    // Dart legt daraufhin seinen UDP-Socket neu an: Sockets bleiben an dem Netz,
    // das beim Erzeugen galt, und der App-Start ist meist schneller als dieser Callback.
    private fun notifyDart() = main.post { channel?.invokeMethod("networkChanged", null) }

    // Art-Net läuft im lokalen WLAN. Hat das WLAN kein Internet (z.B. der Access-Point
    // des Dongles), schickt Android die Pakete sonst über die mobilen Daten und sie
    // kommen nie an. Deshalb wird der ganze App-Prozess ans WLAN gebunden.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                wifi = network
                if (internetMode) return
                val ok = cm.bindProcessToNetwork(network)
                Log.i(TAG, "An WLAN gebunden: $network ($ok)")
                notifyDart()
            }

            override fun onLost(network: Network) {
                if (wifi == network) wifi = null
                if (cm.boundNetworkForProcess == network) {
                    cm.bindProcessToNetwork(null)
                    Log.i(TAG, "WLAN weg, Bindung gelöst")
                    notifyDart()
                }
            }
        }
        cm.registerNetworkCallback(request, cb)
        callback = cb
    }

    override fun onDestroy() {
        callback?.let {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(it)
            cm.bindProcessToNetwork(null)
        }
        callback = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "DmxControl"
    }
}
