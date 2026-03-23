import { Server } from 'socket.io';
import { db, auth } from '../config/firebase.js';
import logger from '../utils/logger.js';

let io;
const LIKE_BATCH_MS = 2000;
const likeQueues = new Map();

/**
 * Socket.io Authentication Middleware
 */
const authenticateSocket = async (socket, next) => {
    try {
        const token = socket.handshake.auth?.token || socket.handshake.query?.token;
        if (!token) {
            return next(new Error('Authentication error: No token provided'));
        }

        const decodedToken = await auth.verifyIdToken(token);
        socket.user = { uid: decodedToken.uid };
        next();
    } catch (err) {
        logger.error({ err: err.message }, '[SOCKET] Auth failed');
        next(new Error('Authentication error: Invalid token'));
    }
};

export const initSocket = (server) => {
    io = new Server(server, {
        cors: {
            origin: "*",
            methods: ["GET", "POST"]
        }
    });

    // Apply authentication
    io.use(authenticateSocket);

    io.on('connection', (socket) => {
        const userId = socket.user.uid;
        logger.info(`🔌 Socket connected: ${socket.id} (User: ${userId})`);

        // --- Post Rooms (Dynamic/Public Metadata) ---
        socket.on('join_post', (postId) => {
            socket.join(`post_${postId}`);
            logger.debug(`User ${userId} joined post_${postId}`);
        });

        socket.on('leave_post', (postId) => {
            socket.leave(`post_${postId}`);
            logger.debug(`User ${userId} left post_${postId}`);
        });

        // --- Chat Rooms (Private Messaging) ---
        socket.on('join_chat', async (chatId) => {
            try {
                // 1. Validate membership
                const chatSnap = await db.collection('chats').doc(chatId).get();
                if (!chatSnap.exists) return socket.emit('error', 'Chat not found');
                
                const chatData = chatSnap.data();
                if (!chatData.participants.includes(userId)) {
                    logger.warn(`🚫 User ${userId} attempted unauthorized join to chat ${chatId}`);
                    return socket.emit('error', 'Unauthorized');
                }

                // 2. Join
                socket.join(`chat_${chatId}`);
                logger.debug(`💬 User ${userId} joined chat_${chatId}`);
            } catch (err) {
                logger.error({ err: err.message }, '[SOCKET] join_chat failed');
            }
        });

        socket.on('leave_chat', (chatId) => {
            socket.leave(`chat_${chatId}`);
            logger.debug(`🚶 User ${userId} left chat_${chatId}`);
        });

        // --- Real-time Interactions (Typing, Presence) ---
        socket.on('typing_start', (chatId) => {
            socket.to(`chat_${chatId}`).emit('user_typing', { chatId, userId, typing: true });
        });

        socket.on('typing_stop', (chatId) => {
            socket.to(`chat_${chatId}`).emit('user_typing', { chatId, userId, typing: false });
        });

        socket.on('disconnect', () => {
            logger.info(`🔌 Socket disconnected: ${socket.id} (User: ${userId})`);
        });
    });

    return io;
};

/**
 * Broadcasts a like update with batching
 */
export const broadcastLikeUpdate = (postId, finalCount, userId) => {
    if (!io) return;

    if (!likeQueues.has(postId)) {
        likeQueues.set(postId, { lastCount: finalCount, timer: null });
    }

    const entry = likeQueues.get(postId);
    entry.lastCount = finalCount;

    if (!entry.timer) {
        entry.timer = setTimeout(() => {
            io.to(`post_${postId}`).emit('like_update', {
                postId,
                likeCount: entry.lastCount
            });
            likeQueues.delete(postId);
        }, LIKE_BATCH_MS);
    }
};

/**
 * Broadcasts a comment update instantly
 */
export const broadcastCommentUpdate = (postId, commentCount, newComment = null) => {
    if (!io) return;
    io.to(`post_${postId}`).emit('comment_update', {
        postId,
        commentCount,
        newComment
    });
};

export const getIO = () => io;
