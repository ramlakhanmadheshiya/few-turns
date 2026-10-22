package com.theramlakhan.fewturns.share;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Saves the share picture to the gallery and opens the system share sheet with it.
 *
 * GDScript use: Engine.get_singleton("FewTurnsShare").saveImage(path, name) and
 * .share(path, "image/png", text). `path` is a file in the app's own storage
 * (user://), which Godot's FileProvider already covers.
 */
public class FewTurnsSharePlugin extends GodotPlugin {
	private String error = "";

	public FewTurnsSharePlugin(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "FewTurnsShare";
	}

	@UsedByGodot
	public String lastError() {
		return error;
	}

	/** Copies a PNG into the gallery under Pictures/Few Turns (Android 10+). */
	@UsedByGodot
	public boolean saveImage(String path, String displayName) {
		Activity activity = getActivity();
		if (activity == null) {
			error = "no activity";
			return false;
		}
		if (Build.VERSION.SDK_INT < 29) {
			error = "saving to the gallery needs Android 10 or newer";
			return false;
		}
		try {
			ContentResolver resolver = activity.getContentResolver();
			ContentValues values = new ContentValues();
			values.put(MediaStore.MediaColumns.DISPLAY_NAME, displayName);
			values.put(MediaStore.MediaColumns.MIME_TYPE, "image/png");
			values.put(MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/Few Turns");
			values.put(MediaStore.MediaColumns.IS_PENDING, 1);
			Uri uri = resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values);
			if (uri == null) {
				error = "the gallery refused the file";
				return false;
			}
			try (InputStream in = new FileInputStream(path); OutputStream out = resolver.openOutputStream(uri)) {
				byte[] buf = new byte[64 * 1024];
				int n;
				while ((n = in.read(buf)) > 0) {
					out.write(buf, 0, n);
				}
			}
			values.clear();
			values.put(MediaStore.MediaColumns.IS_PENDING, 0);
			resolver.update(uri, values, null, null);
			return true;
		} catch (Exception e) {
			error = "save: " + e;
			return false;
		}
	}

	/** Opens the system share sheet with a file and a message. */
	@UsedByGodot
	public boolean share(String path, String mime, String text) {
		final Activity activity = getActivity();
		if (activity == null) {
			error = "no activity";
			return false;
		}
		try {
			Intent send = new Intent(Intent.ACTION_SEND);
			send.putExtra(Intent.EXTRA_TEXT, text);
			if (path != null && !path.isEmpty()) {
				Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", new File(path));
				send.setType(mime);
				send.putExtra(Intent.EXTRA_STREAM, uri);
				send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			} else {
				send.setType("text/plain");
			}
			final Intent chooser = Intent.createChooser(send, "Share your shot");
			chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			activity.runOnUiThread(() -> activity.startActivity(chooser));
			return true;
		} catch (Exception e) {
			error = "share: " + e;
			return false;
		}
	}
}
