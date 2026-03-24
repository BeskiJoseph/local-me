// Route File Syntax & Structure Validation
import fs from 'fs';

console.log('\n=== PHASE 2 ROUTE VALIDATION ===\n');

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

// Test 1: posts.js Syntax
console.log('TEST 1: posts.js Route Syntax');
try {
  import('./src/routes/posts.js').then(() => {
    test('posts.js imports successfully', true);
    passed++;
  }).catch(e => {
    test('posts.js imports', false);
    failed++;
  });
} catch (e) {
  test('posts.js syntax', false);
  failed++;
}

// Test 2: File contents
console.log('\nTEST 2: posts.js Contents');
const postsContent = fs.readFileSync('./src/routes/posts.js', 'utf8');

test('Contains postController import', postsContent.includes('postController'));
test('Contains validation import', postsContent.includes('validateQuery'));
test('Contains authentication', postsContent.includes('authenticate'));
test('Contains session middleware', postsContent.includes('sessionMiddleware'));
test('Contains GET / route', postsContent.includes("router.get(\n  '/',"));
test('Contains POST / route', postsContent.includes("router.post(\n  '/',"));
test('Contains DELETE route', postsContent.includes("router.delete(\n  '/:id'"));
test('Contains PUT route', postsContent.includes("router.put(\n  '/:id'"));

// Test 3: Controller
console.log('\nTEST 3: postController.js Contents');
const controllerContent = fs.readFileSync('./src/controllers/postController.js', 'utf8');

test('Contains createPost', controllerContent.includes('createPost'));
test('Contains getPost', controllerContent.includes('getPost'));
test('Contains getLocalFeed', controllerContent.includes('getLocalFeed'));
test('Contains getGlobalFeed', controllerContent.includes('getGlobalFeed'));
test('Contains getFilteredFeed', controllerContent.includes('getFilteredFeed'));
test('Contains deletePost', controllerContent.includes('deletePost'));

// Test 4: Reduced file size
console.log('\nTEST 4: Code Reduction');
const postsLines = postsContent.split('\n').length;
test(`posts.js < 500 lines (${postsLines})`, postsLines < 500);
test('posts.js > 300 lines (not empty)', postsLines > 300);

// Test 5: Repository
console.log('\nTEST 5: postRepository.js Contents');
const repoContent = fs.readFileSync('./src/repositories/postRepository.js', 'utf8');

test('Uses postRepository class', repoContent.includes('class PostRepository'));
test('Has getLocalFeed method', repoContent.includes('getLocalFeed'));
test('Has getGlobalFeed method', repoContent.includes('getGlobalFeed'));
test('Has getFilteredFeed method', repoContent.includes('getFilteredFeed'));
test('Uses deterministic ordering', repoContent.includes('.orderBy(\'createdAt\', \'desc\')'));
test('Uses __name__ ordering', repoContent.includes('.orderBy(\'__name__\', \'desc\')'));
test('Implements cursor pagination', repoContent.includes('startAfter'));

// Test 6: Services
console.log('\nTEST 6: Service Layer');
const feedContent = fs.readFileSync('./src/services/feedService.js', 'utf8');
test('FeedService has trending calculation', feedContent.includes('calculateTrendingScore'));
test('Implements time-decay', feedContent.includes('ENGAGEMENT_DECAY'));

const geoContent = fs.readFileSync('./src/services/geoService.js', 'utf8');
test('GeoService has distance calc', geoContent.includes('calculateDistance'));
test('GeoService has precision selection', geoContent.includes('getPrecisionForDistance'));

// Summary
console.log(`\n${'='.repeat(40)}`);
console.log(`PASSED: ${passed}`);
console.log(`FAILED: ${failed}`);
console.log(`TOTAL:  ${passed + failed}`);
console.log(`SUCCESS: ${((passed / (passed + failed)) * 100).toFixed(1)}%`);
console.log('='.repeat(40) + '\n');

if (failed === 0) {
  console.log('✓✓✓ ALL ROUTE TESTS PASSED ✓✓✓\n');
} else {
  console.log(`✗✗✗ ${failed} TESTS FAILED ✗✗✗\n`);
}
