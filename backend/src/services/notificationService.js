import { db } from '../config/firebase.js';
import admin from 'firebase-admin';
import MetricsService from './metricsService.js';
import logger from '../utils/logger.js';

/**
 * Centralized Notification Service
 * Handles Firestore notification documents and FCM Push Notifications
 */
class NotificationService {
    /**
     * Send a notification to a specific user
     * @param {string} toUserId - Recipient UID
     * @param {Object} payload - Notification data
     */
    static async notify(toUserId, { 
        fromUserId, 
        fromUserName, 
        fromUserProfileImage, 
        type, 
        title, 
        body, 
        postId, 
        postThumbnail, 
        commentText,
        chatId,
        metadata = {} 
    }) {
        if (!toUserId || toUserId === fromUserId) return null;

        try {
            // 🔴 2 FIX: Deduplicate Rapid Events (e.g., Like/Unlike cycles)
            const tenMinsAgo = new Date(Date.now() - 10 * 60 * 1000);
            const existingQuery = db.collection('notifications')
                .where('toUserId', '==', toUserId)
                .where('fromUserId', '==', fromUserId)
                .where('type', '==', type)
                .where('isRead', '==', false)
                .where('timestamp', '>=', tenMinsAgo);

            if (postId) {
                const dupCheck = await existingQuery.where('postId', '==', postId).limit(1).get();
                if (!dupCheck.empty) return null;
            } else if (type === 'follow') {
                const dupCheck = await existingQuery.limit(1).get();
                if (!dupCheck.empty) return null;
            }

            // 1. Create Firestore Notification Document
            const notificationData = {
                toUserId,
                fromUserId,
                fromUserName,
                fromUserProfileImage,
                type,
                isRead: false,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                ...metadata
            };

            if (postId) notificationData.postId = postId;
            if (postThumbnail) notificationData.postThumbnail = postThumbnail;
            if (commentText) notificationData.commentText = commentText;
            if (chatId) notificationData.chatId = chatId;
            if (title) notificationData.title = title;
            if (body) notificationData.body = body;

            const docRef = await db.collection('notifications').add(notificationData);

            // 2. Fetch Recipient's FCM Token
            const userDoc = await db.collection('users').doc(toUserId).get();
            const fcmToken = userDoc.data()?.fcmToken;

            if (fcmToken) {
                // 3. Send FCM Push Notification
                try {
                    const message = {
                        notification: {
                            title: title || this._getDefaultTitle(type, fromUserName),
                            body: body || this._getDefaultBody(type, commentText),
                        },
                        data: {
                            type,
                            notificationId: docRef.id,
                            ...(postId ? { postId } : {}),
                            ...(chatId ? { chatId } : {}),
                            click_action: 'FLUTTER_NOTIFICATION_CLICK',
                        },
                        token: fcmToken,
                        android: {
                            priority: 'high',
                            notification: {
                                sound: 'default',
                                clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                            }
                        },
                        apns: {
                            payload: {
                                aps: {
                                    sound: 'default',
                                    badge: 1,
                                }
                            }
                        }
                    };

                    await admin.messaging().send(message);
                    logger.info({ toUserId, type, notificationId: docRef.id }, 'FCM Push Notification Sent');
                } catch (fcmError) {
                    logger.error({ error: fcmError.message, toUserId }, 'FCM Send Failed');
                    
                    // 🔴 4 FIX: Token Management (Cleanup invalid tokens)
                    const errorCode = fcmError.code;
                    if (errorCode === 'messaging/registration-token-not-registered' || 
                        errorCode === 'messaging/invalid-registration-token') {
                        logger.warn({ toUserId }, 'Clearing invalid FCM token from user profile');
                        await db.collection('users').doc(toUserId).update({
                            fcmToken: admin.firestore.FieldValue.delete(),
                            updatedAt: admin.firestore.FieldValue.serverTimestamp()
                        });
                    }
                }
            }

            // 4. Track Metrics
            MetricsService.track('notifications_sent');

            return docRef.id;
        } catch (error) {
            logger.error({ error: error.message, toUserId, type }, 'Notification Service Error');
            return null;
        }
    }

    static _getDefaultTitle(type, fromUserName) {
        switch (type) {
            case 'like': return 'New Like';
            case 'comment': return 'New Comment';
            case 'follow': return 'New Follower';
            case 'mention': return 'You were mentioned';
            case 'new_message': return `Message from ${fromUserName}`;
            case 'event_join': return 'New Event Attendee';
            default: return 'New Notification';
        }
    }

    static _getDefaultBody(type, commentText) {
        switch (type) {
            case 'like': return 'Someone liked your post';
            case 'comment': return commentText || 'Someone commented on your post';
            case 'follow': return 'Someone started following you';
            case 'mention': return 'Someone mentioned you in a comment';
            case 'new_message': return 'You have a new message';
            case 'event_join': return 'Someone joined your event';
            default: return 'You have a new alert';
        }
    }
}

export default NotificationService;
