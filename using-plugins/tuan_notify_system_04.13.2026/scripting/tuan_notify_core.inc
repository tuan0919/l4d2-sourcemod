#if defined _tuan_notify_core_included
 #endinput
#endif
#define _tuan_notify_core_included

#define TUAN_NOTIFY_LIBRARY "tuan_notify_core"

native int TuanNotify_PublishInfo(const char[] message);
native int TuanNotify_PublishKill(const char[] message);
native int TuanNotify_IsChatNotificationEnabled();
native int TuanNotify_IsScreenHudNotificationEnabled();
native int TuanNotify_IsKillFeedEnabled();

forward void TuanNotify_OnPublished(const char[] channel, const char[] message, int displayedOnHud);
