package io.v.android.sdl;

import android.util.Log;
import android.os.Bundle;
import android.content.pm.ActivityInfo;
import org.libsdl.app.SDLActivity;

public class VSDLActivity extends SDLActivity {
    private static final String TAG = "SDL";

    /** Called when the activity is first created. */
    @Override
    public void onCreate(Bundle savedInstanceState)
    {
        super.onCreate(savedInstanceState);
        Log.v(TAG, "onCreate()");
        // Force landscape
        //this.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);
    }
    /**
     * This method returns the name of the shared object with the application entry point
     * It can be overridden by derived classes.

    protected String getMainSharedObject() {
        String library;
        String[] libraries = SDLActivity.mSingleton.getLibraries();
        if (libraries.length > 0) {
            library = "lib" + libraries[libraries.length - 1] + ".so";
        } else {
            library = "libmain.so";
        }
        return getContext().getApplicationInfo().nativeLibraryDir + "/" + library;
    }
    */

    /**
     * This method returns the name of the application entry point
     * It can be overridden by derived classes.

    protected String getMainFunction() {
        return "SDL_main";
    }
    */

    /**
     * This method is called by SDL before loading the native shared libraries.
     * It can be overridden to provide names of shared libraries to be loaded.
     * The default implementation returns the defaults. It never returns null.
     * An array returned by a new implementation must at least contain "SDL2".
     * Also keep in mind that the order the libraries are loaded may matter.
     * @return names of shared libraries to be loaded (e.g. "SDL2", "main").
     */
    protected String[] getLibraries() {
        Log.v(TAG, "getLibraries()");
        return new String[] {
            "SDL2",
            // "SDL2_image",
            // "SDL2_mixer",
            // "SDL2_net",
            // "SDL2_ttf",
            "main"
        };
    }
}
