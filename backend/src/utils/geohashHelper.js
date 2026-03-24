/**
 * Geohash Helper - Utilities for geohash calculations
 * 
 * Wraps ngeohash with consistent error handling and validation.
 */

import ngeohash from 'ngeohash';
import logger from './logger.js';

/**
 * Calculate geohash from coordinates with error handling
 */
export function calculateGeohash(lat, lng, precision = 9) {
  try {
    if (lat == null || lng == null) {
      throw new Error('Latitude and longitude are required');
    }

    if (typeof lat !== 'number' || typeof lng !== 'number') {
      throw new Error('Coordinates must be numbers');
    }

    if (lat < -90 || lat > 90) {
      throw new Error('Latitude must be between -90 and 90');
    }

    if (lng < -180 || lng > 180) {
      throw new Error('Longitude must be between -180 and 180');
    }

    if (precision < 1 || precision > 12 || !Number.isInteger(precision)) {
      throw new Error('Precision must be an integer between 1 and 12');
    }

    const hash = ngeohash.encode(lat, lng, precision);
    return hash;
  } catch (error) {
    logger.error({ lat, lng, precision, error }, '[Geohash] Error calculating geohash');
    throw error;
  }
}

/**
 * Get geohash bounds for a range query
 * Returns [min, max] for Firestore .where('geoHash', '>=', min).where('geoHash', '<=', max)
 */
export function getGeohashBounds(geoHash) {
  try {
    if (!geoHash || typeof geoHash !== 'string') {
      throw new Error('geoHash must be a non-empty string');
    }

    const min = geoHash;
    const max = geoHash + '\uf8ff'; // Unicode max character

    return { min, max };
  } catch (error) {
    logger.error({ geoHash, error }, '[Geohash] Error getting geohash bounds');
    throw error;
  }
}

/**
 * Get geohash from coordinates and return bounds
 */
export function getGeohashBoundsFromCoordinates(lat, lng, precision = 9) {
  try {
    const hash = calculateGeohash(lat, lng, precision);
    return getGeohashBounds(hash);
  } catch (error) {
    logger.error({ lat, lng, precision, error }, '[Geohash] Error getting bounds from coordinates');
    throw error;
  }
}

/**
 * Decode geohash to approximate center coordinates
 */
export function decodeGeohash(geoHash) {
  try {
    if (!geoHash || typeof geoHash !== 'string') {
      throw new Error('geoHash must be a non-empty string');
    }

    const bbox = ngeohash.decode_bbox(geoHash);
    // bbox is [minLat, minLon, maxLat, maxLon]
    const centerLat = (bbox[0] + bbox[2]) / 2;
    const centerLng = (bbox[1] + bbox[3]) / 2;

    return {
      lat: centerLat,
      lng: centerLng,
      bounds: {
        minLat: bbox[0],
        minLng: bbox[1],
        maxLat: bbox[2],
        maxLng: bbox[3]
      }
    };
  } catch (error) {
    logger.error({ geoHash, error }, '[Geohash] Error decoding geohash');
    throw error;
  }
}

/**
 * Get neighbors of a geohash (8 cells around it)
 * Useful for expanding search radius
 */
export function getNeighbors(geoHash) {
  try {
    if (!geoHash || typeof geoHash !== 'string') {
      throw new Error('geoHash must be a non-empty string');
    }

    const neighbors = ngeohash.neighbors(geoHash);
    return neighbors; // Returns { right, left, top, bottom, top_right, top_left, bottom_right, bottom_left }
  } catch (error) {
    logger.error({ geoHash, error }, '[Geohash] Error getting neighbors');
    throw error;
  }
}

/**
 * Get list of geohash neighbors as array
 */
export function getNeighborsArray(geoHash) {
  try {
    const neighbors = getNeighbors(geoHash);
    return [
      geoHash, // Include self
      neighbors.top,
      neighbors.bottom,
      neighbors.left,
      neighbors.right,
      neighbors.top_left,
      neighbors.top_right,
      neighbors.bottom_left,
      neighbors.bottom_right
    ].filter(h => h); // Remove any undefined values
  } catch (error) {
    logger.error({ geoHash, error }, '[Geohash] Error getting neighbors array');
    throw error;
  }
}
