package com.bezaleel.file_organizer

import android.app.Activity
import android.content.Intent
import android.content.UriPermission
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.bezaleel.file_organizer/saf"
    private var pendingResult: MethodChannel.Result? = null

    private val openTree =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri: Uri? ->
            val result = pendingResult
            pendingResult = null
            if (uri == null) {
                result?.error("cancelled", "Folder picker closed", null)
                return@registerForActivityResult
            }
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            runCatching {
                contentResolver.takePersistableUriPermission(uri, flags)
            }
            result?.success(uri.toString())
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        try {
            when (call.method) {
                "pickTree" -> pickTree(result)
                "list" -> result.success(list(args["uri"].toString()))
                "existsDir" -> result.success(existsDir(args["uri"].toString(), args["name"].toString()))
                "ensureDir" -> result.success(ensureDir(args["uri"].toString(), args["name"].toString()))
                "childUri" -> result.success(childUri(args["uri"].toString(), args["name"].toString()))
                "move" -> {
                    move(
                        args["srcUri"].toString(),
                        args["destDir"].toString(),
                        args["destName"].toString(),
                    )
                    result.success(null)
                }
                "copy" -> {
                    copy(
                        args["srcUri"].toString(),
                        args["destDir"].toString(),
                        args["destName"].toString(),
                    )
                    result.success(null)
                }
                "delete" -> {
                    delete(args["uri"].toString())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("saf", e.message ?: e.toString(), null)
        }
    }

    private fun pickTree(result: MethodChannel.Result) {
        pendingResult = result
        openTree.launch(null)
    }

    private fun doc(uri: String): DocumentFile? =
        runCatching {
            DocumentFile.fromTreeUri(this, Uri.parse(uri))
                ?: DocumentFile.fromSingleUri(this, Uri.parse(uri))
        }.getOrNull()

    private fun list(uri: String): List<Map<String, Any?>> {
        val folder = doc(uri) ?: return emptyList()
        if (!folder.isDirectory) return emptyList()
        return folder.listFiles().mapNotNull { child ->
            if (child.name == null) return@mapNotNull null
            mapOf(
                "name" to child.name,
                "size" to (child.length() ?: 0L),
                "isDir" to child.isDirectory,
                "modified" to (child.lastModified() ?: 0L),
            )
        }
    }

    private fun existsDir(uri: String, name: String): Boolean =
        doc(uri)?.findFile(name)?.isDirectory == true

    private fun ensureDir(uri: String, name: String): String {
        val folder = doc(uri)
            ?: throw IllegalStateException("Cannot open directory handle: $uri")
        val existing = folder.findFile(name)
        if (existing != null && existing.isDirectory) return existing.uri.toString()
        val created = folder.createDirectory(name)
            ?: throw IllegalStateException("Could not create folder '$name'")
        return created.uri.toString()
    }

    private fun childUri(uri: String, name: String): String? =
        doc(uri)?.findFile(name)?.uri?.toString()

    private fun move(srcUri: String, destDir: String, destName: String) {
        val src = doc(srcUri) ?: throw IllegalStateException("Source not found: $srcUri")
        val destFolder = doc(destDir)
            ?: throw IllegalStateException("Destination not found: $destDir")
        copy(src, destFolder, destName)
        src.delete()
    }

    private fun copy(src: DocumentFile, destFolder: DocumentFile, destName: String) {
        val inStream = contentResolver.openInputStream(src.uri)
            ?: throw IllegalStateException("Cannot read ${src.name}")
        val existing = destFolder.findFile(destName)
        if (existing != null) existing.delete()
        val created = destFolder.createFile(mimeOf(src), destName)
            ?: throw IllegalStateException("Cannot create '$destName'")
        inStream.use { input ->
            contentResolver.openOutputStream(created.uri).use { output ->
                if (output != null) input.copyTo(output)
            }
        }
    }

    private fun copy(srcUri: String, destDir: String, destName: String) {
        val src = doc(srcUri) ?: throw IllegalStateException("Source not found: $srcUri")
        val destFolder = doc(destDir)
            ?: throw IllegalStateException("Destination not found: $destDir")
        copy(src, destFolder, destName)
    }

    private fun delete(uri: String) {
        doc(uri)?.delete()
    }

    private fun mimeOf(file: DocumentFile): String =
        file.type ?: "application/octet-stream"
}
