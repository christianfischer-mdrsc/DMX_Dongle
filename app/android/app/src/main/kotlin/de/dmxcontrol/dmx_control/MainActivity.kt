package de.dmxcontrol.dmx_control

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var callback: ConnectivityManager.NetworkCallback? = null

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
                val ok = cm.bindProcessToNetwork(network)
                Log.i(TAG, "An WLAN gebunden: $network ($ok)")
            }

            override fun onLost(network: Network) {
                if (cm.boundNetworkForProcess == network) {
                    cm.bindProcessToNetwork(null)
                    Log.i(TAG, "WLAN weg, Bindung gelöst")
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
