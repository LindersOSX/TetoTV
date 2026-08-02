package dev.animetv.anime_tv

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat

class AiringReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val mediaId = intent.getLongExtra("mediaId", 0)
        val episode = intent.getIntExtra("episode", 1)
        val title = intent.getStringExtra("title") ?: "Anime"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "airing_reminders"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Airing reminders",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val open = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("tetotv:///anime/$mediaId?episode=$episode"),
            context,
            MainActivity::class.java,
        )
        val pending = PendingIntent.getActivity(
            context,
            mediaId.toInt(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("$title is airing soon")
            .setContentText("Episode $episode starts in about 10 minutes.")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .build()
        manager.notify((mediaId * 31 + episode).toInt(), notification)
    }
}
