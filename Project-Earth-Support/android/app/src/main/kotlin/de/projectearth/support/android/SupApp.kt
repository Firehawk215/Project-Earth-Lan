package de.projectearth.support.android

import android.app.Application

class SupApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SupRuntime.init(this)
    }
}
