import { Server } from 'socket.io';
import logger from '../utils/logger.js';

let io;
const LIKE_BATCH_MS = 2000; // 2 seconds batching
const likeQueues = new Map(); // postId -> { count, timers }

export const initSocket = (server) => {
    io = new Server(server, {
        cors: {
            origin: "*",
            methods: ["GET", "POST"]
        }
    });

    io.on('connection', (socket) => {
        logger.info(`🔌 Socket connected: ${socket.id}`);

        socket.on('join_post', (postId) => {
            socket.join(`post_${postId}`);
            logger.debug(`User ${socket.id} joined post_${postId}`);
        });

        socket.on('leave_post', (postId) => {
            socket.leave(`post_${postId}`);
            logger.debug(`User ${socket.id} left post_${postId}`);
        });

        socket.on('disconnect', () => {
            logger.info(`🔌 Socket disconnected: ${socket.id}`);
        });
    });

    return io;
};

/**
 * Broadcasts a like update with batching
 */
export const broadcastLikeUpdate = (postId, finalCount, userId) => {
    if (!io) return;

    // Batching Logic (YouTube Style)
    if (!likeQueues.has(postId)) {
        likeQueues.set(postId, { lastCount: finalCount, timer: null });
    }

    const entry = likeQueues.get(postId);
    entry.lastCount = finalCount;

    if (!entry.timer) {
        entry.timer = setTimeout(() => {
            // Send to all in room except potentially the initiator if we had their socketId
            // But since we trigger this from REST, we don't have socketId easily.
            // Client-side will handle ignoring its own optimistic update.
            io.to(`post_${postId}`).emit('like_update', {
                postId,
                likeCount: entry.lastCount
            });

            logger.debug(`📢 Batched like update sent for ${postId}: ${entry.lastCount}`);
            likeQueues.delete(postId);
        }, LIKE_BATCH_MS);
    }
};

export const getIO = () => io;
