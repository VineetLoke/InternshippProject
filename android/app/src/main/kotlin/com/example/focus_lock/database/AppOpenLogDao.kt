package com.example.focus_lock.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query

@Dao
interface AppOpenLogDao {
    @Insert
    fun insert(log: AppOpenLog)

    @Query("SELECT * FROM app_open_logs WHERE date = :date ORDER BY id DESC")
    fun getLogsForDate(date: String): List<AppOpenLog>

    @Query("SELECT COUNT(*) FROM app_open_logs WHERE date = :date AND package_name = :packageName")
    fun getOpenCountForDate(date: String, packageName: String): Int

    @Query("SELECT * FROM app_open_logs WHERE date = :date AND package_name = :packageName ORDER BY id DESC")
    fun getLogsForDateAndPackage(date: String, packageName: String): List<AppOpenLog>

    @Query("DELETE FROM app_open_logs WHERE date < :date")
    fun deleteOlderThan(date: String)
}
