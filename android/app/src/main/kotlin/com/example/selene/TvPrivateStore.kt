package org.moontechlab.selene

import android.content.Context
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

class TvPrivateStore(context: Context) {
    private val file = File(context.noBackupFilesDir, "selene-tv.json")
    fun read(): Map<String, Any?> {
        val json = if (file.exists()) JSONObject(file.readText()) else JSONObject().apply {
            put("clientId", UUID.randomUUID().toString()); put("name", Build.MODEL.take(64)); put("trusted", JSONObject())
        }.also { save(it) }
        @Suppress("UNCHECKED_CAST") return unpack(json) as Map<String, Any?>
    }
    fun write(value: Map<*, *>) { save(JSONObject(value)) }
    private fun save(value: JSONObject) {
        val temporary = File(file.parentFile, "selene-tv.tmp")
        temporary.writeText(value.toString()); check(temporary.renameTo(file))
    }
    private fun unpack(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { unpack(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { unpack(value.get(it)) }
        else -> value
    }
}
