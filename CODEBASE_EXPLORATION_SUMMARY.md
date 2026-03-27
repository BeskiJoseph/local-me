# Codebase Structure & Feed/Posts Architecture Summary

**Last Updated**: March 24, 2026
**Total Files**: ~155 files (108 Dart, 47 JavaScript/Node.js)

---

## 1. DIRECTORY STRUCTURE OVERVIEW

### Root Level
```
C:\Users\beski\Downloads\testpro-main (1)
├── backend/                    # Node.js Express API server
├── testpro-main/              # Flutter mobile application
├── lib/                        # Shared Flutter lib (legacy reference)
└── [Documentation files]      # Phase reports and architecture docs
```

---

## 2. BACKEND ARCHITECTURE (Node.js/Express)

### 2.1 Directory Structure
```
backend/src/
├── config/                     # Firebase & environment config
│   ├── env.js                 # Environment variables
│   └── firebase.js            # Firebase Admin SDK initialization
├── controllers/               # HTTP request/response handlers
│   └── postController.js      # Post CRUD & feed operations
├── routes/                    # API endpoint definitions
│   ├── posts.js              # Main feed/post endpoints
│   ├── posts.js.backup       # Legacy version (50KB)
│   ├── posts_refactored.js   # Alternative implementation
│   ├── interactions.js       # Like/follow/engagement endpoints
│   ├── profiles.js           # User profile endpoints
│   ├── auth.js               # Authentication endpoints
│   ├── chats.js              # Messaging endpoints
│   ├── search.js             # Search functionality
│   └── [other routes]
├── models/                    # Data models & validation
│   └── post.model.js         # Post schema & validation
├── repositories/             # Database access layer (SINGLE SOURCE OF TRUTH)
│   └── postRepository.js     # All Firestore post queries (452 lines)
├── services/                 # Business logic layer
│   ├── feedService.js        # FEED ENGINE - Main feed algorithm (584 lines)
│   ├── geoService.js         # Geographic calculations
│   ├── geoIndex.js           # Geohash indexing
│   ├── InteractionGuard.js   # Interaction rate limiting
│   ├── RiskEngine.js         # Security/risk scoring
│   ├── PenaltyBox.js         # User penalty tracking
│   ├── userContextService.js # User preferences & cache
│   ├── notificationService.js # Push notifications
│   ├── socketService.js      # WebSocket connections
│   ├── metricsService.js     # Performance metrics
│   └── auditService.js       # Audit logging
├── middleware/               # Express middleware
│   ├── auth.js              # JWT authentication
│   ├── validation.js        # Request validation schemas
│   ├── errorHandler.js      # Global error handling
│   ├── rateLimiter.js       # Rate limiting
│   ├── progressiveLimiter.js # Progressive rate limiting
│   ├── security.js          # Security headers
│   ├── httpLogger.js        # HTTP request logging
│   ├── deviceContext.js     # Device fingerprinting
│   ├── interactionVelocity.js # Interaction speed tracking
│   ├── uploadLimits.js      # File upload limits
│   └── sanitize.js          # Input sanitization
├── utils/                    # Utility functions
│   ├── logger.js            # Structured logging
│   ├── paginationHelper.js  # Pagination utilities
│   ├── geohashHelper.js     # Geohash calculations
│   ├── userDisplayName.js   # User name formatting
│   ├── sanitizer.js         # HTML/JS sanitization
│   ├── contentFilter.js     # Content moderation
│   └── videoProcessor.js    # Video processing
├── index.js                  # Server entry point
├── app.js                    # Express app configuration
└── [test files]             # Test suites & validation scripts
```

### 2.2 Key Backend Files for Feed/Posts

| File | Lines | Purpose |
|------|-------|---------|
| `services/feedService.js` | 584 | **FEED ENGINE** - Core ranking & merging logic |
| `repositories/postRepository.js` | 452 | **Single source of truth** for all post DB queries |
| `controllers/postController.js` | 583 | HTTP request/response coordination |
| `routes/posts.js` | 523 | API endpoints: GET/POST/DELETE /posts |
| `models/post.model.js` | ~150 | Post schema validation |
| `services/geoService.js` | 125 | Geographic operations |

---

## 3. FLUTTER APP ARCHITECTURE

### 3.1 Directory Structure
```
testpro-main/lib/
├── config/                   # App configuration
├── core/                     # Core state & utilities
│   ├── auth/                # Authentication state
│   ├── events/              # Event broadcasting
│   ├── session/             # Session management
│   ├── state/               # STATE MANAGEMENT (CRITICAL)
│   │   ├── feed_controller.dart     # Mutable feed list operations
│   │   ├── feed_session.dart        # Session-level seen IDs tracking
│   │   ├── post_state.dart          # Central post store (Riverpod)
│   │   └── provider_container.dart  # Provider initialization
│   └── utils/               # Utilities
├── models/                  # Data classes
│   ├── post.dart           # Post data model (242 lines)
│   ├── paginated_response.dart  # Pagination wrapper
│   ├── api_response.dart   # API response model
│   ├── comment.dart        # Comment model
│   ├── user_profile.dart   # User profile model
│   └── [other models]
├── repositories/           # Data access layer
│   ├── post_repository.dart     # Post operations (300 lines)
│   ├── social_repository.dart   # Social features
│   └── user_repository.dart     # User operations
├── services/              # Business logic & API calls
│   ├── backend_service.dart     # HTTP client facade (1249 lines)
│   ├── post_service.dart        # Post service (216 lines)
│   ├── auth_service.dart        # Authentication
│   ├── notification_service.dart # Push notifications
│   ├── location_service.dart    # Location operations
│   ├── media_upload_service.dart # Media handling
│   ├── socket_service.dart      # WebSocket client
│   └── [other services]
├── screens/               # Full-screen UI pages
│   ├── feed_screen.dart        # Main feed (2540 lines)
│   ├── reels_feed_screen.dart   # Video feed (29080 lines)
│   ├── new_post_screen.dart     # Post creation
│   ├── edit_post_screen.dart    # Post editing
│   ├── post_insights_screen.dart # Analytics
│   ├── event_post_card.dart     # Event card display
│   └── [other screens]
├── widgets/              # Reusable UI components
│   ├── feed/             # Feed components
│   │   ├── paginated_feed_list.dart      # Paginated feed widget
│   │   ├── recommended_feed_list.dart    # Recommended posts
│   │   └── feed_shimmer.dart             # Loading skeleton
│   ├── post/             # Post components
│   │   ├── post_card.dart                # Post display card
│   │   ├── post_action_row.dart          # Like/comment/share
│   │   ├── post_header.dart              # Author info
│   │   └── post_media_display.dart       # Media rendering
│   ├── home/             # Home page widgets
│   ├── event_card/       # Event display
│   └── [other widgets]
├── utils/               # Utility functions
├── ui/                  # UI design system
└── shared/              # Shared utilities
```

### 3.2 Key Flutter Files for Feed/Posts

| File | Lines | Purpose |
|------|-------|---------|
| `services/backend_service.dart` | 1249 | HTTP client facade + API calls |
| `core/state/post_state.dart` | 452 | Central Riverpod post store |
| `core/state/feed_controller.dart` | 179 | Mutable feed list controller |
| `repositories/post_repository.dart` | 300 | Post data operations |
| `services/post_service.dart` | 216 | Post business logic |
| `models/post.dart` | 242 | Post data class |
| `screens/feed_screen.dart` | 2540 | Main feed screen |
| `widgets/feed/paginated_feed_list.dart` | ~200 | Paginated list component |

---

## 4. FEED/POSTS FLOW ARCHITECTURE

### 4.1 Backend Feed Engine (PHASE 4)

#### Algorithm Overview: `feedService.js`

**getHybridFeed() Pipeline** (8 steps):

```
1. FETCH LOCAL POSTS (pageSize * 2)
   └─ Query Firestore with geohash bounds

2. FETCH GLOBAL POSTS (pageSize * 2)
   └─ Query Firestore global collection

3. MERGE SOURCES
   └─ [local posts] + [global posts] = ~80 posts

4. DEDUPLICATE
   └─ Remove posts already seen 
