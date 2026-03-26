package com.example.wifi_ftp

import android.content.Intent
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.fastshare/file_path"
    private val TAG = "FastShareNative"
    private val PICK_FILE_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRealPath" -> {
                        val uriString = call.argument<String>("uri")
                        Log.d(TAG, "Resolving URI: $uriString")
                        if (uriString == null) {
                            result.error("INVALID_ARG", "uri is null", null)
                        } else {
                            try {
                                val uri = Uri.parse(uriString)
                                val path = getRealPathFromUri(this, uri)
                                Log.d(TAG, "Resolved Path: $path")
                                result.success(path)
                            } catch (e: Exception) {
                                Log.e(TAG, "Resolution Error", e)
                                result.error("RESOLVE_FAILED", e.message, null)
                            }
                        }
                    }
                    "pickFile" -> {
                        if (pendingResult != null) {
                            result.error("ALREADY_ACTIVE", "A pick request is already pending", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*" // Let user pick anything, including 4GB movies
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        }
                        startActivityForResult(intent, PICK_FILE_REQUEST_CODE)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK_FILE_REQUEST_CODE) {
            val result = pendingResult
            pendingResult = null
            if (resultCode == RESULT_OK && data != null) {
                val uris = mutableListOf<Map<String, Any>>()
                
                // Multiple files
                if (data.clipData != null) {
                    val count = data.clipData!!.itemCount
                    for (i in 0 until count) {
                        val uri = data.clipData!!.getItemAt(i).uri
                        uris.add(getUriMetaData(uri))
                    }
                } 
                // Single file
                else if (data.data != null) {
                    uris.add(getUriMetaData(data.data!!))
                }
                
                result?.success(uris)
            } else {
                result?.success(null)
            }
        }
    }

    private fun getUriMetaData(uri: Uri): Map<String, Any> {
        val meta = mutableMapOf<String, Any>("uri" to uri.toString())
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE)
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
                if (nameIndex >= 0) meta["name"] = cursor.getString(nameIndex)
                if (sizeIndex >= 0) meta["size"] = cursor.getLong(sizeIndex)
            }
        }
        return meta
    }

    /**
     * Resolves a content:// URI to a real filesystem path.
     *
     * Handles:
     *  - Document provider URIs (com.android.providers.downloads, media, external)
     *  - raw MediaStore URIs (content://media/...)
     *  - file:// URIs
     *
     * Returns null when the file lives in the cloud (Google Drive, etc.) and
     * no local copy exists. The Dart side then falls back to a stream copy.
     */
    private fun getRealPathFromUri(context: Context, uri: Uri): String? {
        // ── file:// ──────────────────────────────────────────────────────────
        if (uri.scheme == "file") return uri.path

        // ── content:// ───────────────────────────────────────────────────────
        if (uri.scheme != "content") return null

        // ── Document URI (API 19+) ───────────────────────────────────────────
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT &&
            DocumentsContract.isDocumentUri(context, uri)
        ) {
            val authority = uri.authority ?: ""
            val docId = DocumentsContract.getDocumentId(uri)

            // Downloads provider
            if (authority == "com.android.providers.downloads.documents") {
                if (docId.startsWith("raw:")) {
                    return docId.removePrefix("raw:")
                }
                if (docId.startsWith("msf:")) {
                    // Modern downloads — query MediaStore.Downloads
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        val id = docId.removePrefix("msf:")
                        val downloadUri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                        val contentUri = ContentUris.withAppendedId(downloadUri, id.toLongOrNull() ?: return null)
                        return getDataColumn(context, contentUri, null, null)
                    }
                }
                // Numeric ID — legacy Downloads
                val id = docId.toLongOrNull()
                if (id != null) {
                    val contentUri = ContentUris.withAppendedId(
                        Uri.parse("content://downloads/public_downloads"), id
                    )
                    return getDataColumn(context, contentUri, null, null)
                }
                return null
            }

            // Media provider
            if (authority == "com.android.providers.media.documents") {
                val split = docId.split(":").toTypedArray()
                val type = split[0]
                val mediaId = split.getOrNull(1)?.toLongOrNull() ?: return null
                val contentUri: Uri = when (type) {
                    "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    "video" -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                    "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                    else -> return null
                }
                val realUri = ContentUris.withAppendedId(contentUri, mediaId)
                return getDataColumn(context, realUri, null, null)
            }

            // External storage provider
            if (authority == "com.android.externalstorage.documents") {
                val split = docId.split(":").toTypedArray()
                val storageType = split[0]
                val relativePath = split.getOrNull(1) ?: return null
                if (storageType == "primary") {
                    return "${Environment.getExternalStorageDirectory()}/$relativePath"
                }
                // SD card – enumerate mounted volumes
                val externalDirs = context.getExternalFilesDirs(null)
                for (file in externalDirs) {
                    val path = file?.absolutePath ?: continue
                    val mountRoot = path.substringBefore("/Android/data")
                    if (path.contains(storageType)) {
                        return "$mountRoot/$relativePath"
                    }
                }
                return null
            }
        }

        // ── Plain content:// (e.g. content://media/external/video/media/42) ──
        return getDataColumn(context, uri, null, null)
    }

    private fun getDataColumn(
        context: Context,
        uri: Uri,
        selection: String?,
        selectionArgs: Array<String>?
    ): String? {
        val column = MediaStore.MediaColumns.DATA
        val projection = arrayOf(column)
        var cursor: Cursor? = null
        return try {
            cursor = context.contentResolver.query(uri, projection, selection, selectionArgs, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(column)
                if (index >= 0) cursor.getString(index) else null
            } else null
        } catch (e: Exception) {
            null
        } finally {
            cursor?.close()
        }
    }
}
