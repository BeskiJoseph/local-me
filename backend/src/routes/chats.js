import express from 'express';
import authenticate from '../middleware/auth.js';
import NotificationService from '../services/notificationService.js';
import MetricsService from '../services/metricsService.js';
import admin, { db } from '../config/firebase.js';
import logger from '../utils/logger.js';
import { progressiveLimiter } from '../middleware/progressiveLimiter.js';

const router = express.Router();

/**
 * Helper: Generate deterministic 1:1 chat key
 */
const getChatKey = (uid1, uid2) => [uid1, uid2].sort().join('_');

/**
 * @route   GET /api/chats
 * @desc    List all active chats for the current user
 */
router.get('/', authenticate, async (req, res, next) => {
    try {
        const userId = req.user.uid;
        
        // Find chats where user is a participant
        const snapshot = await db.collection('chats')
            .where('participants', 'array-contains', userId)
            .orderBy('lastTimestamp', 'desc')
            .limit(50)
            .get();

        const chats = snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data()
        }));

        return res.json({ success: true, data: chats, error: null });
    } catch (err) {
        logger.error({ err: err.message }, '[CHATS] List failed');
        next(err);
    }
});

/**
 * @route   POST /api/chats
 * @desc    Find or create a 1:1 chat with another user
 * @body    { targetUserId: string }
 */
router.post('/', authenticate, async (req, res, next) => {
    try {
        const { targetUserId } = req.body;
        const currentUserId = req.user.uid;

        if (!targetUserId || targetUserId === currentUserId) {
            return res.status(400).json({
                success: false,
                data: null,
                error: { message: 'Invalid target user' }
            });
        }

        const chatKey = getChatKey(currentUserId, targetUserId);

        // Check for existing chat with this key
        const existing = await db.collection('chats')
            .where('chatKey', '==', chatKey)
            .limit(1)
            .get();

        if (!existing.empty) {
            return res.json({
                success: true,
                data: { id: existing.docs[0].id, ...existing.docs[0].data() },
                error: null
            });
        }

        // Fetch target user info for metadata
        const targetUserSnap = await db.collection('users').doc(targetUserId).get();
        if (!targetUserSnap.exists) {
            return res.status(404).json({
                success: false,
                data: null,
                error: { message: 'Target user not found' }
            });
        }
        const targetUserData = targetUserSnap.data();

        // Create new chat document
        const newChat = {
            chatKey,
            participants: [currentUserId, targetUserId],
            participantInfo: {
                [currentUserId]: {
                    displayName: req.user.displayName || 'Me',
                    photoURL: req.user.photoURL || ''
                },
                [targetUserId]: {
                    displayName: targetUserData.displayName || targetUserData.username || 'User',
                    photoURL: targetUserData.profileImageUrl || ''
                }
            },
            unreadCounts: {
                [currentUserId]: 0,
                [targetUserId]: 0
            },
            lastMessage: '',
            lastSenderId: '',
            lastTimestamp: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            type: 'direct'
        };

        const docRef = await db.collection('chats').add(newChat);
        
        return res.json({
            success: true,
            data: { id: docRef.id, ...newChat },
            error: null
        });
    } catch (err) {
        logger.error({ err: err.message }, '[CHATS] Create failed');
        next(err);
    }
});

/**
 * @route   POST /api/chats/:chatId/messages
 * @desc    Send a message and update chat metadata in a transaction
 */
router.post('/:chatId/messages', authenticate, progressiveLimiter('chat_message', true), async (req, res, next) => {
    try {
        const { chatId } = req.params;
        const { text } = req.body;
        const userId = req.user.uid;
        const now = new Date(); // Request-time timestamp for comparison

        if (!text || text.trim().length === 0) {
            return res.status(400).json({ success: false, error: { message: 'Message text is required' } });
        }

        const chatRef = db.collection('chats').doc(chatId);
        let messageResult; // To store the message data created within the transaction
        let participants; // Capture for notification logic

        await db.runTransaction(async (transaction) => {
            const chatDoc = await transaction.get(chatRef);
            if (!chatDoc.exists) throw new Error('Chat not found');

            participants = chatDoc.data().participants;
            if (!participants.includes(userId)) throw new Error('Unauthorized');

            const messageRef = chatRef.collection('messages').doc();
            const messageData = {
                senderId: userId,
                text: text.trim(),
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                type: 'text',
                status: 'sent'
            };

            // 1. Write message
            transaction.set(messageRef, messageData);
            messageResult = { id: messageRef.id, ...messageData }; // Capture for response

            // 2. Prepare metadata update
            const otherUser = participants.find(p => p !== userId);
            const currentData = chatDoc.data();
            const currentLastTimestamp = currentData.lastTimestamp?.toDate?.() || new Date(0);

            const updates = {
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                [`unreadCounts.${otherUser}`]: admin.firestore.FieldValue.increment(1)
            };

            // 🔴 1 FIX: Only update lastMessage if this message is actually newer
            if (now >= currentLastTimestamp) {
                updates.lastMessage = text.trim().substring(0, 100);
                updates.lastTimestamp = admin.firestore.FieldValue.serverTimestamp();
                updates.lastSenderId = userId;
            }

            transaction.update(chatRef, updates);
        });

        // 3. Track Metrics
        MetricsService.track('messages');

        // 4. Trigger Notification (Async/Background)
        db.collection('users').doc(userId).get()
            .then(senderDoc => {
                const senderData = senderDoc.data();
                const senderName = senderData.displayName || 'Someone';
                const senderImage = senderData.profileImageUrl;
                const otherUser = participants.find(p => p !== userId);

                NotificationService.notify(otherUser, {
                    fromUserId: userId,
                    fromUserName: senderName,
                    fromUserProfileImage: senderImage,
                    type: 'new_message',
                    body: text.trim(),
                    chatId
                });
            })
            .catch(err => logger.error({ err: err.message }, '[CHAT_NOTIFY] Failed to send notification'));
        
        return res.json({ success: true, data: messageResult, error: null });
    } catch (err) {
        logger.error({ err: err.message }, '[CHATS] Send failed');
        res.status(err.message === 'Unauthorized' ? 403 : 404).json({
            success: false,
            error: { message: err.message }
        });
    }
});

/**
 * @route   POST /api/chats/:chatId/read
 * @desc    Reset unread count for current user
 */
router.post('/:chatId/read', authenticate, async (req, res, next) => {
    try {
        const { chatId } = req.params;
        const userId = req.user.uid;

        const chatRef = db.collection('chats').doc(chatId);
        await chatRef.update({
            [`unreadCounts.${userId}`]: 0
        });

        return res.json({ success: true, data: null, error: null });
    } catch (err) {
        logger.error({ err: err.message }, '[CHATS] Read reset failed');
        next(err);
    }
});

export default router;
