// Phase 2 Test Suite
import postRepository from './src/repositories/postRepository.js';
import feedService from './src/services/feedService.js';
import geoService from './src/services/geoService.js';
import { calculateGeohash, getGeohashBounds } from './src/utils/geohashHelper.js';
import { validatePost, mapDocToPost } from './src/models/post.model.js';
import { schemas } from './src/middleware/validation.js';

let passed = 0, failed = 0;

function test(msg, condition) {
  if (condition) {
    console.log(`✓ ${msg}`);
    passed++;
  } else {
    console.log(`✗ ${msg}`);
    failed++;
  }
}

console.log('\n=== PHASE 2 ARCHITECTURE TEST ===\n');

// Test 1: Validation
console.log('TEST 1: Validation Layer');
const validPost = { title: 'Test', body: 'Body', authorId: 'user' };
test('Valid post passes', validatePost(validPost).valid === true);
test('Invalid post fails', validatePost({ body: 'No title' }).valid === false);

// Test 2: Geohash
console.log('\nTEST 2: Geohash Helper');
try {
  const hash = calculateGeohash(40.7128, -74.0060, 9);
  test('Geohash calculates', hash && typeof hash === 'string');
  const { min, max } = getGeohashBounds(hash);
  test('Bounds generated', min && max && min < max);
} catch (e) {
  test('Geohash error', false);
}

// Test 3: Geo Service
console.log('\nTEST 3: Geo Service');
const dist = geoService.calculateDistance(40.7128, -74.0060, 34.0522, -118.2437);
test(`Distance NYC-LA: ${dist.toFixed(0)}km`, dist > 3900 && dist < 4000);

const p1 = geoService.getPrecisionForDistance(0.05);
const p2 = geoService.getPrecisionForDistance(5);
test(`Precision scales down: ${p1} > ${p2}`, p1 > p2);

// Test 4: Models
console.log('\nTEST 4: Post Model');
const mockDoc = {
  id: 'test',
  exists: true,
  data: () => ({ title: 'T', body: 'B', likeCount: 42 })
};
const post = mapDocToPost(mockDoc);
test('Document maps correctly', post && post.id === 'test');
test('Fields preserved', post.likeCount === 42);

// Test 5: Repository
console.log('\nTEST 5: Repository Methods');
const methods = ['getPostById', 'getLocalFeed', 'getGlobalFeed', 'getFilteredFeed'];
const allPresent = methods.every(m => typeof postRepository[m] === 'function');
test(`All ${methods.length} methods present`, allPresent);

// Test 6: Service
console.log('\nTEST 6: Feed Service');
const serviceMethods = ['getLocalFeed', 'getGlobalFeed', 'calculateTrendingScore'];
const serviceOk = serviceMethods.every(m => typeof feedService[m] === 'function');
test(`All ${serviceMethods.length} methods present`, serviceOk);

const mockPost = {
  likeCount: 10,
  commentCount: 5,
  viewCount: 100,
  createdAt: { toMillis: () => Date.now() - 3600000 }
};
const score = feedService.calculateTrendingScore(mockPost);
test(`Trending score: ${score.toFixed(2)}`, typeof score === 'number' && score > 0);

// Test 7: Validation Schemas
console.log('\nTEST 7: Validation Schemas');
const { error: e1 } = schemas.feedQuery.validate({
  feedType: 'local', lat: 40.7128, lng: -74.0060, limit: 20
});
test('Valid feed query', !e1);

const { error: e2 } = schemas.feedQuery.validate({
  feedType: 'local', lat: 91, lng: -74.0060
});
test('Invalid latitude rejected', !!e2);

// Test 8: Architecture
console.log('\nTEST 8: Architecture');
test('Repository layer', postRepository !== undefined);
test('Service layer', feedService !== undefined);
test('Models layer', validatePost !== undefined);
test('Validation middleware', schemas !== undefined);

// Summary
console.log(`\n${'='.repeat(40)}`);
console.log(`PASSED: ${passed}`);
console.log(`FAILED: ${failed}`);
console.log(`TOTAL:  ${passed + failed}`);
console.log(`SUCCESS: ${((passed / (passed + failed)) * 100).toFixed(1)}%`);
console.log('='.repeat(40) + '\n');

if (failed === 0) {
  console.log('✓✓✓ ALL TESTS PASSED ✓✓✓\n');
  process.exit(0);
} else {
  console.log(`✗✗✗ ${failed} TESTS FAILED ✗✗✗\n`);
  process.exit(1);
}
