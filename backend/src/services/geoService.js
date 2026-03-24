/**
 * Geo Service - Centralized geographic calculations
 * 
 * Handles:
 * - Haversine distance calculations
 * - Geohash precision selection based on distance
 * - Geohash bounding box generation
 */

import logger from '../utils/logger.js';

const EARTH_RADIUS_KM = 6371;

class GeoService {
  /**
   * Calculate great-circle distance between two points
   * @param {number} lat1 - Latitude of point 1
   * @param {lon1} lon1 - Longitude of point 1
   * @param {number} lat2 - Latitude of point 2
   * @param {number} lon2 - Longitude of point 2
   * @returns {number} Distance in kilometers
   */
  calculateDistance(lat1, lon1, lat2, lon2) {
    if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
      return Infinity;
    }

    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return EARTH_RADIUS_KM * c;
  }

  /**
   * Get optimal geohash precision based on how far we've scrolled
   * 
   * Precision levels (from ngeohash):
   * - 9: ~44m x 44m cell
   * - 8: ~177m x 177m cell
   * - 7: ~709m x 709m cell
   * - 6: ~2.8km x 2.8km cell
   * - 5: ~11.2km x 11.2km cell
   * - 4: ~45km x 45km cell
   * - 3: ~180km x 180km cell
   * - 2: ~720km x 720km cell
   * - 1: entire world
   */
  getPrecisionForDistance(distanceKm) {
    if (distanceKm < 0.1) return 9; // Very close: detailed cells
    if (distanceKm < 0.5) return 8;
    if (distanceKm < 2) return 7;
    if (distanceKm < 10) return 6;
    if (distanceKm < 50) return 5;
    if (distanceKm < 200) return 4;
    if (distanceKm < 800) return 3;
    if (distanceKm < 3000) return 2;
    return 1; // Entire world
  }

  /**
   * Get geohash range (min/max) for a given center and precision
   * 
   * This creates a bounding box using geohash ranges.
   * All posts with geoHash in [min, max] will be returned by the query.
   */
  getGeohashBounds(geoHash) {
    if (!geoHash || geoHash.length === 0) {
      throw new Error('geoHash is required');
    }

    // Geohash ranges for simple bounding box
    // Min: keep as-is
    // Max: append 'zzz...' to get all hashes starting with this prefix
    const geohashMin = geoHash;
    const geohashMax = geoHash + '\uf8ff'; // Unicode max character

    return {
      min: geohashMin,
      max: geohashMax
    };
  }

  /**
   * Get the neighboring geohash cells
   * Used for expanding search radius when results are insufficient
   * 
   * @param {string} geoHash - Base geohash
   * @returns {Array<string>} Array of 8 neighboring geohashes at same precision
   */
  getNeighbors(geoHash) {
    // Simplified: just return same geohash
    // A full implementation would compute actual neighbors
    // For now, this is handled by reducing precision instead
    return [geoHash];
  }

  /**
   * Validate latitude/longitude coordinates
   */
  validateCoordinates(lat, lng) {
    if (lat == null || lng == null) {
      throw new Error('Latitude and longitude are required');
    }

    if (typeof lat !== 'number' || typeof lng !== 'number') {
      throw new Error('Latitude and longitude must be numbers');
    }

    if (lat < -90 || lat > 90) {
      throw new Error('Latitude must be between -90 and 90');
    }

    if (lng < -180 || lng > 180) {
      throw new Error('Longitude must be between -180 and 180');
    }

    return true;
  }

  /**
   * Validate geohash
   */
  validateGeohash(geoHash) {
    if (!geoHash || typeof geoHash !== 'string') {
      throw new Error('geoHash must be a non-empty string');
    }

    if (geoHash.length < 1 || geoHash.length > 12) {
      throw new Error('geoHash must be between 1 and 12 characters');
    }

    // Valid characters in geohash: 0-9, b-z (excluding a)
    if (!/^[0-9b-z]+$/i.test(geoHash)) {
      throw new Error('geoHash contains invalid characters');
    }

    return true;
  }
}

export default new GeoService();
