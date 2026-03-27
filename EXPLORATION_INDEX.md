# Codebase Exploration - Complete Reference

Generated: March 24, 2026

## Overview

This exploration provides a comprehensive understanding of the testpro application's architecture, with special focus on feed/posts functionality across the Node.js backend and Flutter frontend.

**Total Files Analyzed**: ~155 files
- 108 Dart files (Flutter)
- 47 JavaScript files (Backend)

## Key Findings

### 1. Architecture Type
- **Backend**: Node.js/Express with Firebase Firestore
- **Frontend**: Flutter with Riverpod state management
- **Feed Engine**: Phase 4 - Hybrid ranking with cursor pagination

### 2. Feed/Posts Implementation
- **Type**: Hybrid feed (local + global merged and ranked)
- **Pagination**: Cursor-based (not offset)
- **Ranking**: Lightweight heuristic (recency 50% + engagement 30% + distance 20%)
- **Deduplication**: 5-layer system (server session, server hard, client session, client memory, tombstones)

### 3. Key Statistics
- Feed Engine: 584 lines (feedService.js)
- Post Repository: 452 lines (postRepository.js)
- Main Feed Screen: 2,540 lines (feed_screen.dart)
- HTTP Client: 1,249 lines (backend_service.dart)
- Post Store: 452 lines (post_state.dart)

## Documentation Files

Three comprehensive reference documents have been generated:

### 1. CODEBASE_EXPLORATION_SUMMARY.txt (8.8 KB)
**Complete architectural overview**

Contains:
- Full directory structure breakdown
- File listing with line counts and purposes
- Backend services, controllers, repositories
- Flutter state management and services
- Database structure (Firestore)
- Deduplication strategy (5 layers)
- Pagination implementation details
- API endpoints and request/response formats
- Critical entry points
- Full data flow diagrams

**Best for**: Understanding the complete architecture, finding specific files

### 2. FEED_ARCHITECTURE_DIAGRAM.txt (12 KB)
**Visual flow diagrams and sequences**

Contains:
- Hybrid feed generation pipeline (8-step visual)
- Client-side feed loading sequence
- Pagination flow diagram
- Like/interaction flow
- Feed cycling mechanism
- 5-layer deduplication visual
- Ranking score calculation with examples
- Post creation to feed display flow

**Best for**: Understanding data flows, visual learners, sequence understanding

### 3. QUICK_REFERENCE.txt (8.0 KB)
**Quick lookup guide for developers**

Contains:
- Absolute file paths for key files
- Flow references (loading, paginating, liking, creating)
- Main classes and structures
- Ranking weights
- API endpoints
- Deduplication checklist
- Key services reference
- Firestore indexes
- Critical decision points
- Testing checklist
- Debugging tips

**Best for**: Quick lookups, during development, debugging

## File Organization

```
Workspace Root: C:\Users\beski\Downloads\testpro-main (1)

├── backend/                          # Node.js API Server
│   └── src/
│       ├── services/feedService.js          # FEED ENGINE (core)
│       ├── repositories/postRepository.js   # DB queries (single source of truth)
│       ├── controllers/postController.js    # HTTP handlers
│       ├── routes/posts.js                  # API endpoints
│       └── [middleware, models, utils]
│
├── testpro-main/                     # Flutter Mobile App
│   └── lib/
│       ├── core/state/
│       │   ├── feed_controller.dart         # Mutable feed list
│       │   ├── post_state.dart              # Riverpod store
│       │   └── feed_session.dart            # Session tracking
│       ├── services/
│       │   ├── backend_service.dart         # HTTP client
│       │   └── post_service.dart            # Post logic
│       ├── repositories/post_repository.dart # API operations
│       ├── screens/feed_screen.dart         # Main UI
│       └── [models, widgets, utils]
│
└── [Documentation & Reference Files]
    ├── CODEBASE_EXPLORATION_SUMMARY.txt
    ├── FEED_ARCHITECTURE_DIAGRAM.txt
    ├── QUICK_REFERENCE.txt
    └── [Phase reports]
```

## Quick Start Guide

### To Understand the Feed Engine:
1. Start with: **FEED_ARCHITECTURE_DIAGRAM.txt** (visual flow)
2. Read: **CODEBASE_EXPLORATION_SUMMARY.txt** Section 4 (Feed Engine Architecture)
3. Review: `backend/src/services/feedService.js` (code)

### To Find a Specific File:
1. Use: **QUICK_REFERENCE.txt** - "Absolute Paths" section
2. Or: **CODEBASE_EXPLORATION_SUMMARY.txt** - Directory Structure

### To Debug an Issue:
1. Check: **QUICK_REFERENCE.txt** - "Debugging Tips"
2. Follow: **FEED_ARCHITECTURE_DIAGRAM.txt** - relevant flow diagram
3. Reference: **CODEBASE_EXPLORATION_SUMMARY.txt** - implementation details

### To Understand Data Flow:
1. See: **FEED_ARCHITECTURE_DIAGRAM.txt** - flow diagrams
2. Check: **QUICK_REFERENCE.txt** - flow references

## Core Concepts

### Feed Types
- **Global**: All users worldwide, sorted by createdAt + ranking
- **Local**: Users within geographic bounds, by geohash
- **Hybrid**: Merged local + global with ranking
- **Filtered**: By author, category, or location
- **Explore**: Trending posts by engagement

### Ranking Formula
```
Score = (recency * 0.5) + (engagement * 0.3) + (distance * 0.2)

Where:
- recency = 1 / (1 + hoursOld)
- engagement = (likes + comments*2 + views*0.1) / 100
- distance = 1 / (1 + distanceKm)
```

### Deduplication Layers
1. **Server Session**: Tracks per-feedType seenIds (2-hr TTL)
2. **Server Hard**: Removes duplicates from merged batch
3. **Client Session**: FeedSession.seenIds per feedType
4. **Client Memory**: existingIds.contains() check before adding
5. **Tombstones**: Optimistic delete markers

### Pagination
- **Type**: Cursor-based (createdAt DESC, postId DESC)
- **Size**: 15 posts per page (default)
- **Cursor Format**: {createdAt, postId, authorName}
- **Switch to POST**: When seenIds > 500 (URL length > 2000 chars)

## Technology Stack

**Backend**:
- Node.js 18+
- Express.js framework
- Firebase Firestore database
- Custom geohash utilities

**Frontend**:
- Flutter framework
- Dart language
- Riverpod state management
- HTTP client for API calls

## Important Notes

### Critical Decision Points
1. Ranking ONLY on merged batch (safe, in-memory)
2. Cursor pagination prevents duplicates
3. Hard dedup BEFORE limit (ensures diversity)
4. Ranking score NOT used for pagination cursor
5. Post-based pagination for large seenIds
6. Session-level dedup per feedType

### Production Considerations
- Geohash precision: 9 characters (~22 meters)
- Session TTL: 2 hours
- Page size: 15 posts (tunable)
- Memory dedup: Essential for UI smoothness
- URL length threshold: 2000 chars (414 error prevention)

## Navigation Guide

### Understanding Complete Architecture
→ **CODEBASE_EXPLORATION_SUMMARY.txt**

### Visual Learners / Flow Understanding
→ **FEED_ARCHITECTURE_DIAGRAM.txt**

### During Development / Debugging
→ **QUICK_REFERENCE.txt**

### Finding Specific Code
→ **QUICK_REFERENCE.txt** (Absolute Paths section)

### Understanding Data Models
→ **CODEBASE_EXPLORATION_SUMMARY.txt** Section 5 (Database)

### API Integration
→ **CODEBASE_EXPLORATION_SUMMARY.txt** Section 8 (API Endpoints)

### State Management
→ **CODEBASE_EXPLORATION_SUMMARY.txt** Section 9 (Flutter State)

## Summary

This codebase implements a sophisticated social feed system with:

✅ **Server-side**: Hybrid feed generation with intelligent ranking
✅ **Client-side**: Efficient state management with Riverpod
✅ **Database**: Firestore with proper indexing for queries
✅ **Deduplication**: Multi-layer strategy preventing any duplicates
✅ **Pagination**: Cursor-based for stability and performance
✅ **Ranking**: Lightweight heuristic (no ML, no DB changes)
✅ **Geospatial**: Full location-based features with geohashing
✅ **Interactions**: Optimistic updates for responsive UI

The architecture is **production-ready** with comprehensive error handling, logging, and performance optimization.

---

**Generated by**: Codebase Exploration Tool
**Date**: March 24, 2026
**Scope**: Complete feed/posts architecture analysis
