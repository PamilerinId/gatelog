package ng.gatelog.gatelog_guard

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService

/**
 * Caller ID for the gate: notes the number and time of each incoming call, in memory only, so
 * the app can offer the caller's home ("Is it Mrs Adeyemi, 14B?"), send the number masked on the
 * records of that call, and offer it as a resident's new number after a confirmed callback.
 *
 * It never blocks, silences, rejects or changes a call: every call is allowed through exactly
 * as it came. The number is never written to disk or logged. Android binds this service only
 * while the app holds RoleManager.ROLE_CALL_SCREENING; without the role nothing here runs and
 * the app works the same, with no hint.
 */
class GateCallScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        try {
            val incoming = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                callDetails.callDirection == Call.Details.DIRECTION_INCOMING
            val number = callDetails.handle?.schemeSpecificPart
            if (incoming && !number.isNullOrBlank()) LastCall.note(number, System.currentTimeMillis())
        } finally {
            // Allow the call, unchanged.
            respondToCall(callDetails, CallResponse.Builder().build())
        }
    }
}

/** The last incoming call, in memory. Gone when the process ends. */
object LastCall {
    @Volatile private var number: String? = null
    @Volatile private var at: Long = 0

    @Synchronized
    fun note(n: String, whenMs: Long) {
        number = n
        at = whenMs
    }

    @Synchronized
    fun read(): Map<String, Any>? {
        val n = number ?: return null
        return mapOf("number" to n, "at" to at)
    }
}
