package com.example.focus_lock.storage.database

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "app_open_logs")
data class AppOpenLog(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,

    @ColumnInfo(name = "app_name")
    val appName: String,

    @ColumnInfo(name = "package_name")
    val packageName: String,

    @ColumnInfo(name = "timestamp")
    val timestamp: String,

    @ColumnInfo(name = "date")
    val date: String
)
