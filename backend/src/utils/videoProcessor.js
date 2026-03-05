import ffmpeg from 'fluent-ffmpeg';
import ffmpegStatic from 'ffmpeg-static';
import logger from './logger.js';

ffmpeg.setFfmpegPath(ffmpegStatic);

/**
 * Get metadata for a video file
 * @param {string} filePath 
 * @returns {Promise<Object>}
 */
export const getVideoMetadata = (filePath) => {
    return new Promise((resolve, reject) => {
        ffmpeg.ffprobe(filePath, (err, metadata) => {
            if (err) {
                logger.error('Error getting video metadata', { filePath, error: err.message });
                return reject(err);
            }
            resolve(metadata);
        });
    });
};

/**
 * Process video: trim to maxDuration and compress
 * @param {string} inputPath 
 * @param {string} outputPath 
 * @param {number} maxDuration - In seconds
 * @returns {Promise<string>}
 */
export const processVideo = (inputPath, outputPath, maxDuration = 300) => {
    return new Promise((resolve, reject) => {
        let command = ffmpeg(inputPath)
            .videoCodec('libx264')
            .audioCodec('aac')
            .format('mp4')
            .outputOptions([
                '-crf 23', // Compression level (lower = better quality, 18-23 is standard)
                '-preset faster',
                '-movflags +faststart' // Progressive download
            ]);

        // Trim if longer than maxDuration
        command = command.duration(maxDuration);

        command
            .on('start', (commandLine) => {
                logger.info('Started ffmpeg processing', { commandLine });
            })
            .on('error', (err) => {
                logger.error('Error processing video', { error: err.message, inputPath });
                reject(err);
            })
            .on('end', () => {
                logger.info('Video processing finished', { outputPath });
                resolve(outputPath);
            })
            .save(outputPath);
    });
};
