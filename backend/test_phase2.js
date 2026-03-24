/**
 * Phase 2 Architecture Testing
 * 
 * Tests:
 * 1. Repository layer - Firestore queries
 * 2. Service layer - Business logic
 * 3. Controller layer - HTTP handling
 * 4. Validation - Input validation
 * 5. End-to-end feed flows
 */

import postRepository from './src/repositories/postRepository.js';
import feedService from './src/services/feedService.js';
import geoService from './src/services/geoService.js';
import { calculateGeohash, getGeohashBounds } from './src/utils/geohashHelper.js';
import { validatePost, mapDocToPost } from './src/models/post.model.js';
import { schemas } from './src/middleware/validation.js';
import logger from './src/utils/logger.js';

// Color codes for output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[36m'
};

let testsPassed = 0;
let testsFailed = 0;
let testsSkipped = 0;

function log(message, type = 'info') {
  const timestamp = new Date().toISOString();
  switch(type) {
    case 'pass':
      console.log(`${colors.green}✓ PASS${colors.reset} [${timestamp}] ${message}`);
      testsPassed++;
      break;
    case 'fail':
      console.log(`${colors.red}✗ FAIL${colors.reset} [${timestamp}] ${message}`);
      testsFailed++;
      break;
    case 'skip':
      console.log(`${colors.yellow}⊘ SKIP${colors.reset} [${timestamp}] ${message}`);
      testsSkipped++;
      break;
    case 'info':
      console.log(`${colors.blue}ℹ INFO${colors.reset} [${timestamp}] ${message}`);
      break;
    case 'section':
      console.log(`\n${colors.blue}═══════════════════════════════════════${colors.reset}`);
      console.log(`${colors.blue}${message}${colors.reset}`);
      console.log(`${colors.blue}═══════════════════════════════════════${colors.reset}\n`);
      break;
  }
}

// ============================================================
// TEST 1: Validation Layer
// ============================================================
log('TEST SUITE 1: Validation Layer', 'section');

function testValidation() {
  try {
    log('Testing Post validation schema');
    
    // Valid post
    const validPost = {
      title: 'Valid Post',
      body: 'This is a valid post body',
      authorId: 'user123',
      city: 'New York',
      country: 'USA',
      visibility: 'public',
      status: 'active'
    };
    
    const result1 = validatePost(validPost);
    if (result1.valid) {
      log('Valid post accepted correctly', 'pass');
    } else {
      log('Valid post rejected: ' + result1.errors.join(', '), 'fail');
    }

    // Invalid post (missing title)
    const invalidPost = {
      body: 'Body without title',
      authorId: 'user123'
    };
    
    const result2 = validatePost(invalidPost);
    if (!result2.valid) {
      log('Invalid post rejected correctly', 'pass');
    } else {
      log('Invalid post accepted (should have failed)', 'fail');
    }

    // Test Joi schema validation
    const { error, value } = schemas.post.validate(validPost);
    if (!error) {
      log('Joi schema validation passed', 'pass');
    } else {
      log('Joi schema validation failed: ' + error.message, 'fail');
    }

  } catch (error) {
    log('Validation test error: ' + error.message, 'fail');
  }
}

// ============================================================
// TEST 2: Geohash Helper
// ============================================================
log('TEST SUITE 2: Geohash Helper', 'section');

function testGeohashHelper() {
  try {
    log('Testing geohash calculation');
    
    // Test coordinates (New York)
    const lat = 40.7128;
    const lng = -74.0060;
    
    try {
      const hash = calculateGeohash(lat, lng, 9);
      log(`Geohash for (${lat}, ${lng}): ${hash}`, 'pass');
      
      // Test bounds
      const { min, max } = getGeohashBounds(hash);
      log(`Geohash bounds: ${min} to ${max}`, 'pass');
      
    } catch (error) {
      log('Geohash calculation error: ' + error.message, 'fail');
    }

    // Test invalid coordinates
    try {
      calculateGeohash(91, 0, 9); // Invalid latitude
      log('Invalid latitude accepted (should reject)', 'fail');
    } catch (error) {
      log('Invalid latitude rejected correctly', 'pass');
    }

    try {
      calculateGeohash(40, 181, 9); // Invalid longitude
      log('Invalid longitude accepted (should reject)', 'fail');
    } catch (error) {
      log('Invalid longitude rejected correctly', 'pass');
    }

  } catch (error) {
    log('Geohash test error: ' + error.message, 'fail');
  }
}

// ============================================================
// TEST 3: Geo Service
// ============================================================
log('TEST SUITE 3: Geo Service', 'section');

function testGeoService() {
  try {
    log('Testing Haversine distance calculation');
    
    // NYC to LA distance should be ~3944 km
    const nycLat = 40.7128, nycLng = -74.0060;
    const laLat = 34.0522, laLng = -118.2437;
    
    const distance = geoService.calculateDistance(nycLat, nycLng, laLat, laLng);
    const isReasonable = distance > 3900 && distance < 4000;
    
    if (isReasonable) {
      log(`NYC to LA distance: ${distance.toFixed(2)} km (expected ~3944) ✓`, 'pass');
    } else {
      log(`NYC to LA distance: ${distance.toFixed(2)} km (expected ~3944) ✗`, 'fail');
    }

    // Test precision selection
    log('Testing geohash precision selection');
    const p1 = geoService.getPrecisionForDistance(0.05); // Very close
    const p2 = geoService.getPrecisionForDistance(5); // Local area
    const p3 = geoService.getPrecisionForDistance(100); // Regional
    const p4 = geoService.getPrecisionForDistance(2000); // National
    
    if (p1 > p2 && p2 > p3 && p3 > p4) {
      log(`Precision correctly scales: 0.05km=${p1}, 5km=${p2}, 100km=${p3}, 2000km=${p4}`, 'pass');
    } else {
      log(`Precision scaling incorrect: ${p1}, ${p2}, ${p3}, ${p4}`, 'fail');
    }

  } catch (error) {
    log('Geo service test error: ' + error.message, 'fail');
  }
}

// ============================================================
// TEST 4: Model Layer
// ============================================================
log('TEST SUITE 4: Model Layer', 'section');

function testModels() {
  try {
    log('Testing Post model');
    
    // Test mapDocToPost
    const mockDoc = {
      id: 'post123',
      exists: true,
      data: () => ({
        title: 'Test Post',
        body: 'Test body',
        authorId: 'user123',
        authorName: 'John Doe',
        city: 'NYC',
        country: 'USA',
        status: 'active',
        visibility: 'public',
        mediaType: 'none',
        likeCount: 42,
        commentCount: 5,
        viewCount: 100,
        engagementScore: 147,
        createdAt: new Date(),
        updatedAt: new Date()
      })
    };

    const post = mapDocToPost(mockDoc);
    
    if (post && post.id === 'post123' && post.likeCount === 42) {
      log('Post model mapping successful', 'pass');
    } else {
      log('Post model mapping failed', 'fail');
    }

    // Test non-existent doc
    const emptyDoc = { exists: false };
    const emptyPost = mapDocToPost(emptyDoc);
    
    if (emptyPost === null) {
      log('Non-existent post returns null', 'pass');
    } else {
      log('Non-existent post should return null', 'fail');
    }

  } catch (error) {
    log('Model test error: ' + error.message, 'fail');
  }
}

// ============================================================
// TEST 5: Repository Layer (Mock)
// ============================================================
log('TEST SUITE 5: Repository Layer', 'section');

function testRepositoryStructure() {
  try {
    log('Verifying repository methods exist');
    
    const methods = [
      'getPostById',
      'createPost',
      'updatePost',
      'deletePost',
      'getLocalFeed',
      'getGlobalFeed',
      'getFilteredFeed',
      'getPostsByAuthor',
      'searchPosts',
      'incrementLikeCount',
      'getPostsByIds'
    ];

    let allPresent = true;
    for (const method of methods) {
      if (typeof postRepository[method] === 'function') {
        log(`Repository.${me
