package de.dmxcontrol.dmx_control

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * USB-Seriell zum Dongle (Handy als USB-Host, USB-C/OTG), ohne Fremdbibliothek.
 *
 * Unterstützt die üblichen Brücken auf ESP32-Boards:
 *  - Silicon Labs CP210x (CP2102/CP2102N, eigene Platine Rev B)
 *  - WCH CH340/CH341 (viele Devkits)
 *  - CDC-ACM (z.B. ESP32-S3 mit nativem USB)
 *
 * DTR und RTS bleiben aus: daran hängt beim ESP32 die Auto-Reset-Schaltung.
 *
 * Kanäle:
 *  MethodChannel "dmx_control/usb": list, open(deviceId, baud), write(bytes), close
 *  EventChannel  "dmx_control/usb/events": {type: data|attached|detached|closed, ...}
 */
class UsbSerialBridge(private val context: Context, messenger: BinaryMessenger) {
    private val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()
    private var events: EventChannel.EventSink? = null

    private var device: UsbDevice? = null
    private var conn: UsbDeviceConnection? = null
    private var dataIface: UsbInterface? = null
    private var ctrlIface: UsbInterface? = null
    private var epIn: UsbEndpoint? = null
    private var epOut: UsbEndpoint? = null
    @Volatile private var reading = false
    private var readThread: Thread? = null
    private var pendingOpen: Pair<MethodChannel.Result, Int>? = null

    private enum class Kind { CP210X, CH34X, CDC }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            val dev = deviceFrom(intent)
            when (intent.action) {
                ACTION_PERMISSION -> {
                    val pending = pendingOpen ?: return
                    pendingOpen = null
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    if (!granted || dev == null) pending.first.error("permission", "USB-Zugriff nicht erlaubt", null)
                    else connect(dev, pending.second, pending.first)
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    if (dev != null && dev.deviceId == device?.deviceId) close("detached")
                    emit(mapOf("type" to "detached"))
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> attached(dev)
            }
        }
    }

    init {
        MethodChannel(messenger, "dmx_control/usb").setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> result.success(usb.deviceList.values.filter { kindOf(it) != null }.map { describe(it) })
                "open" -> {
                    val id = call.argument<Int>("deviceId") ?: -1
                    val baud = call.argument<Int>("baud") ?: 921600
                    open(id, baud, result)
                }
                "write" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) result.error("args", "ByteArray erwartet", null)
                    else {
                        write(bytes)
                        result.success(null)
                    }
                }
                "close" -> {
                    close("app")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "dmx_control/usb/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })

        val filter = IntentFilter().apply {
            addAction(ACTION_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(receiver, filter)
    }

    /** Aus MainActivity (Intent beim Einstecken). */
    fun attached(dev: UsbDevice?) {
        if (dev != null && kindOf(dev) != null) emit(mapOf("type" to "attached", "device" to describe(dev)))
    }

    @Suppress("DEPRECATION")
    private fun deviceFrom(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        else intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)

    private fun kindOf(d: UsbDevice): Kind? = when {
        d.vendorId == 0x10C4 -> Kind.CP210X
        d.vendorId == 0x1A86 -> Kind.CH34X
        (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_CDC_DATA } -> Kind.CDC
        else -> null
    }

    private fun describe(d: UsbDevice): Map<String, Any?> = mapOf(
        "deviceId" to d.deviceId,
        "vendorId" to d.vendorId,
        "productId" to d.productId,
        "name" to (d.productName ?: d.deviceName),
        "manufacturer" to d.manufacturerName,
        "chip" to kindOf(d)?.name,
    )

    private fun open(id: Int, baud: Int, result: MethodChannel.Result) {
        val dev = usb.deviceList.values.firstOrNull { it.deviceId == id }
            ?: return result.error("missing", "Gerät nicht gefunden", null)
        if (usb.hasPermission(dev)) {
            connect(dev, baud, result)
            return
        }
        pendingOpen = Pair(result, baud)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
        val intent = Intent(ACTION_PERMISSION).setPackage(context.packageName)
        usb.requestPermission(dev, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    private fun connect(dev: UsbDevice, baud: Int, result: MethodChannel.Result) {
        close("reopen")
        val kind = kindOf(dev) ?: return result.error("unsupported", "Unbekannter USB-Chip", null)
        val c = usb.openDevice(dev) ?: return result.error("open", "USB-Gerät lässt sich nicht öffnen", null)
        try {
            when (kind) {
                Kind.CP210X, Kind.CH34X -> {
                    val iface = dev.getInterface(0)
                    claim(c, iface)
                    dataIface = iface
                    findBulk(iface)
                    if (kind == Kind.CP210X) initCp210x(c, iface.id, baud) else initCh34x(c, baud)
                }
                Kind.CDC -> {
                    for (i in 0 until dev.interfaceCount) {
                        val it = dev.getInterface(i)
                        if (it.interfaceClass == UsbConstants.USB_CLASS_COMM && ctrlIface == null) ctrlIface = it
                        if (it.interfaceClass == UsbConstants.USB_CLASS_CDC_DATA && dataIface == null) dataIface = it
                    }
                    ctrlIface?.let { claim(c, it) }
                    claim(c, dataIface!!)
                    findBulk(dataIface!!)
                    initCdc(c, ctrlIface?.id ?: 0, baud)
                }
            }
            if (epIn == null || epOut == null) throw IllegalStateException("Keine Bulk-Endpunkte")
        } catch (e: Exception) {
            Log.w(TAG, "USB-Init fehlgeschlagen", e)
            c.close()
            dataIface = null
            ctrlIface = null
            return result.error("init", "USB-Init fehlgeschlagen: ${e.message}", null)
        }
        conn = c
        device = dev
        startReader()
        Log.i(TAG, "USB offen: ${dev.productName} ($kind, $baud Baud)")
        result.success(describe(dev))
    }

    private fun claim(c: UsbDeviceConnection, iface: UsbInterface) {
        if (!c.claimInterface(iface, true)) throw IllegalStateException("Interface ${iface.id} belegt")
    }

    private fun findBulk(iface: UsbInterface) {
        for (i in 0 until iface.endpointCount) {
            val ep = iface.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
            if (ep.direction == UsbConstants.USB_DIR_IN) epIn = ep else epOut = ep
        }
    }

    private fun ctrl(c: UsbDeviceConnection, type: Int, request: Int, value: Int, index: Int, data: ByteArray? = null) {
        val r = c.controlTransfer(type, request, value, index, data, data?.size ?: 0, 1000)
        if (r < 0) throw IllegalStateException("Steuerbefehl 0x${request.toString(16)} fehlgeschlagen")
    }

    // ---- CP210x (AN571) ----
    private fun initCp210x(c: UsbDeviceConnection, iface: Int, baud: Int) {
        val out = 0x41 // Vendor, Interface, Host→Gerät
        ctrl(c, out, 0x00, 0x0001, iface)                     // IFC_ENABLE
        ctrl(c, out, 0x03, 0x0800, iface)                     // SET_LINE_CTL: 8N1
        ctrl(c, out, 0x07, 0x0300, iface)                     // SET_MHS: DTR/RTS aus
        ctrl(c, out, 0x1E, 0, iface, le32(baud))              // SET_BAUDRATE
    }

    // ---- CH340/CH341 (wie im Linux-Treiber ch341) ----
    private fun initCh34x(c: UsbDeviceConnection, baud: Int) {
        val out = 0x40 // Vendor, Device, Host→Gerät
        ctrl(c, out, 0xA1, 0, 0)                              // Serial-Init
        setCh34xBaud(c, baud)
        ctrl(c, out, 0x9A, 0x2518, 0x00C3)                    // LCR: RX+TX an, 8N1
        ctrl(c, out, 0xA1, 0x501F, 0xD90A)
        setCh34xBaud(c, baud)
        ctrl(c, out, 0xA4, 0xFF, 0)                           // Handshake: DTR/RTS aus (invertiert)
    }

    private fun setCh34xBaud(c: UsbDeviceConnection, baud: Int) {
        var factor: Long
        var divisor: Long
        if (baud == 921600) {
            divisor = 7
            factor = 0xF300
        } else {
            factor = 1532620800L / baud
            divisor = 3
            while (factor > 0xFFF0 && divisor > 0) {
                factor = factor shr 3
                divisor--
            }
            factor = 0x10000 - factor
        }
        divisor = divisor or 0x0080
        ctrl(c, 0x40, 0x9A, 0x1312, ((factor and 0xFF00) or divisor).toInt())
        ctrl(c, 0x40, 0x9A, 0x0F2C, (factor and 0xFF).toInt())
    }

    // ---- CDC-ACM ----
    private fun initCdc(c: UsbDeviceConnection, iface: Int, baud: Int) {
        val out = 0x21 // Class, Interface, Host→Gerät
        val coding = le32(baud) + byteArrayOf(0, 0, 8)        // 1 Stopbit, keine Parität, 8 Bit
        ctrl(c, out, 0x20, 0, iface, coding)                  // SET_LINE_CODING
        ctrl(c, out, 0x22, 0, iface)                          // SET_CONTROL_LINE_STATE: DTR/RTS aus
    }

    private fun le32(v: Int) = byteArrayOf(v.toByte(), (v shr 8).toByte(), (v shr 16).toByte(), (v shr 24).toByte())

    // ---- Daten ----
    private fun startReader() {
        val c = conn ?: return
        val ep = epIn ?: return
        reading = true
        readThread = Thread({
            val buf = ByteArray(maxOf(ep.maxPacketSize, 64) * 32)
            while (reading) {
                val n = c.bulkTransfer(ep, buf, buf.size, 200)
                if (n > 0) {
                    val chunk = buf.copyOf(n)
                    main.post { events?.success(mapOf("type" to "data", "data" to chunk)) }
                }
            }
        }, "usb-reader").apply { isDaemon = true; start() }
    }

    private fun write(bytes: ByteArray) {
        writer.execute {
            val c = conn ?: return@execute
            val ep = epOut ?: return@execute
            var off = 0
            while (off < bytes.size) {
                val n = c.bulkTransfer(ep, bytes, off, bytes.size - off, 500)
                if (n <= 0) {
                    Log.w(TAG, "USB-Schreiben fehlgeschlagen")
                    return@execute
                }
                off += n
            }
        }
    }

    private fun emit(event: Map<String, Any?>) = main.post { events?.success(event) }

    fun close(reason: String) {
        reading = false
        readThread?.join(500)
        readThread = null
        val c = conn
        conn = null
        if (c != null) {
            dataIface?.let { c.releaseInterface(it) }
            ctrlIface?.let { c.releaseInterface(it) }
            c.close()
            if (reason != "reopen") emit(mapOf("type" to "closed", "reason" to reason))
        }
        dataIface = null
        ctrlIface = null
        epIn = null
        epOut = null
        device = null
    }

    fun dispose() {
        close("dispose")
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        writer.shutdown()
    }

    companion object {
        private const val TAG = "DmxUsb"
        private const val ACTION_PERMISSION = "de.dmxcontrol.dmx_control.USB_PERMISSION"
    }
}
