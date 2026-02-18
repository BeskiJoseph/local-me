# 🏗️ Architectural Review & Refactoring Plan — LocalMe Flutter App

> **Generated**: 2026-02-17  
> **Safety-first approach**: Every phase is incremental and non-breaking.

---

## 1. Current Architecture Overview

### 1.1 Project Stats

| Metric | Count |
|---|---|
| Dart source files | ~50 |
| `lib/screens/` files (flat) | 20 + 8 signup |
| `lib/widgets/` files | 8 |
| `lib/services/` files | 8 |
| `lib/models/` files | 6 |
| `lib/config/` files | 3 |
| `lib/theme/` files | 1 |
| `lib/utils/` files | 2 |
| Largest file | `welcome_screen.dart` — **1,475 lines** |
| Second largest | `firestore_service.dart` — **953 lines** |

### 1.2 Current Folder Tree
```
lib/
├── main.dart
├── firebase_options.dart
├── config/
│   ├── app_theme.dart        (433 lines — Full ThemeData, colors, gradients, helpers)
│   ├── app_colors.dart        (18 lines  — Separate small color palette)
│   └── app_typography.dart    (59 lines  — Separate text styles)
├── theme/
│   └── app_theme.dart         (81 lines  — SECOND AppTheme class! Name collision)
├── models/
│   ├── post.dart
│   ├── user_profile.dart
│   ├── comment.dart
│   ├── chat_message.dart
│   ├── notification.dart
│   └── signup_data.dart
├── services/
│   ├── auth_service.dart
│   ├── firestore_service.dart (953 lines — God class)
│   ├── backend_service.dart
│   ├── media_upload_service.dart
│   ├── notification_service.dart
│   ├── otp_service.dart
│   ├── r2_service.dart
│   └── geocoding_service.dart
├── screens/
│   ├── welcome_screen.dart      (1,475 lines! — login + animations + custom painters)
│   ├── home_screen.dart         (810 lines — home + NextdoorStylePostCard widget inside)
│   ├── feed_screen.dart         (701 lines — 3 feed list classes in one file)
│   ├── personal_account.dart    (644 lines)
│   ├── post_detail_screen.dart  (829 lines)
│   ├── reels_feed_screen.dart   (747 lines)  
│   ├── new_post_screen.dart     (797 lines)
│   ├── Event post card.dart     (558 lines — filename has space!)
│   ├── edit_profile.dart
│   ├── search_screen.dart
│   ├── activity_screen.dart
│   ├── community_screen.dart
│   ├── group_chat_screen.dart
│   ├── login_page.dart
│   ├── video_player_screen.dart
│   ├── interest_picker_screen.dart
│   ├── verify_email_screen.dart
│   ├── PostTypeSelectorSheet.dart
│   ├── main_navigation_screen.dart
│   └── signup/  (8 files)
├── utils/
│   ├── proxy_helper.dart
│   └── location_service.dart
└── widgets/
    ├── post_card.dart          (659 lines — main post card + shimmer widget)
    ├── modern_post_card.dart   (246 lines — alternate post card)
    ├── bottom_nav_bar.dart
    ├── input_field.dart
    ├── primary_button.dart
    ├── premium_components.dart
    ├── user_search_card.dart
    └── video_slider.dart
```

---

## 2. Critical Issues Identified

### 🔴 Issue 1: Duplicate Post Card Implementations (SEVERE)
There are **4 separate post card widgets** rendering the same `Post` data with different UIs:

| Widget | File | Lines | Where Used |
|---|---|---|---|
| `PostCard` | `widgets/post_card.dart` | 659 | `personal_account.dart`, feed |
| `ModernPostCard` | `widgets/modern_post_card.dart` | 246 | `feed_screen.dart`, `search_screen.dart` |
| `NextdoorStylePostCard` | `home_screen.dart` (embedded!) | ~340 | `home_screen.dart` only |
| `EventPostCard` | `screens/Event post card.dart` | 558 | `post_card.dart` (conditionally) |

**Each reimplements**: like toggle, time formatting, user avatar, action buttons, profile navigation. This is the single biggest source of duplicated logic.

### 🔴 Issue 2: Duplicate Utility Logic (SEVERE)
The following functions are copy-pasted across files:

| Function | Duplicated In |
|---|---|
| `_formatTimeAgo()` | `post_card.dart`, `home_screen.dart` (identical) |
| `_navigateToUserProfile()` | `post_card.dart`, `Event post card.dart`, `post_detail_screen.dart` |
| `_toggleLike()` | `post_card.dart`, `modern_post_card.dart` (different implementations!) |
| `_buildActionButton()` | `home_screen.dart`, `Event post card.dart` |
| `CircleAvatar` with fallback initials | **11 different files** |

### 🔴 Issue 3: Two Conflicting Theme Systems (SEVERE)
- `config/app_theme.dart` — Full design system (`AppTheme` class, 433 lines)
- `theme/app_theme.dart` — Older mini theme (`AppTheme` class, 81 lines)
- `config/app_colors.dart` — Yet another color palette
- `config/app_typography.dart` — Yet another text style set
- `main.dart` — **Ignores all of the above** and defines inline `ThemeData`

**Result**: Colors like `0xFF2563EB` are hardcoded in **6+ files** instead of referencing a constant.

### 🟡 Issue 4: God-Class `FirestoreService` (MODERATE)
953 lines, 42+ methods covering:
- User profiles (CRUD, sync, stats)
- Posts (CRUD, pagination, feeds, recommendations)
- Social (follow/unfollow, likes)
- Comments
- Notifications  
- Chat messages
- Search
- User activity logging

### 🟡 Issue 5: Massive Screen Files (MODERATE)
- `welcome_screen.dart` — 1,475 lines with 3 custom painters embedded
- `home_screen.dart` — 810 lines with `NextdoorStylePostCard` embedded as a 340-line class
- `feed_screen.dart` — 700 lines with 3 classes (`FeedScreen`, `RecommendedFeedList`, `PaginatedFeedList`)
- `post_detail_screen.dart` — 829 lines

### 🟡 Issue 6: Filename Conventions Broken (MODERATE)
- `Event post card.dart` — spaces in filename (anti-pattern)
- `PostTypeSelectorSheet.dart` — PascalCase filename (Dart convention is snake_case)

### 🟢 Issue 7: No State Management (LOW — for current scale)
All state is managed via `setState` + StreamBuilder. No Provider, Bloc, or Riverpod. This works for the current scale but will cause issues as the app grows.

---

## 3. Duplication Heat Map

```
                    PostCard  ModernPC  NextdoorPC  EventPC  PostDetail  ReelsFeed
Like toggle logic      ✅        ✅         ✅         ✅        ✅          ✅
Time formatting        ✅        ✅         ✅         —         —           —
Profile navigation     ✅        ✅         —          ✅        ✅          —
CircleAvatar+fallback  ✅        ✅         ✅         ✅        ✅          ✅
Action buttons row     ✅        ✅         ✅         ✅        ✅          ✅
Media display          ✅        ✅         ✅         —         ✅          ✅
```

**Total estimated duplicated code: ~2,200 lines across 6 widgets.**

---

## 4. Proposed Reusable Component List

### 4.1 Shared Widgets (Extract or Unify)

| Widget Name | Purpose | Replaces |
|---|---|---|
| `UserAvatar` | CircleAvatar with network image + initials fallback + ProxyHelper | 11 manual implementations |
| `PostActions` | Like, Comment, Share button row with optimistic updates | 6 copies across cards |
| `LikeButton` | Standalone optimistic like toggle with StreamBuilder | 4 implementations |
| `PostAuthorHeader` | Author avatar + name + time + more menu with onTap navigation | 4 implementations |
| `PostMediaDisplay` | Unified image/video display with tap gestures | 3 implementations |
| `TimeAgoText` | Formats DateTime to relative time string | 3 `_formatTimeAgo()` functions |
| `EmptyStateWidget` | Configurable icon + title + subtitle + optional CTA button | 8+ inline empty states |
| `ShimmerLoading` | Reusable shimmer effect | 2 implementations |
| `ActionButton` | Icon + label + count button for post interactions | 2 `_buildActionButton()` functions |
| `FollowButton` | Follow/unfollow toggle with loading state | 3 instances |

### 4.2 Shared Utilities (Extract)

| Utility | Purpose | Current Locations |
|---|---|---|
| `time_utils.dart` | `formatTimeAgo(DateTime)` | `post_card.dart`, `home_screen.dart` |
| `navigation_utils.dart` | `navigateToProfile(context, userId)` | 4 files |
| `format_utils.dart` | `formatCount(int)`, number formatting | `personal_account.dart`, others |

---

## 5. Proposed Folder Structure

```
lib/
├── main.dart
├── firebase_options.dart
│
├── core/                              # Foundation layer
│   ├── theme/
│   │   ├── app_theme.dart             # Single unified ThemeData (light + dark)
│   │   ├── app_colors.dart            # Color constants
│   │   └── app_typography.dart        # Text style constants
│   ├── constants/
│   │   └── app_constants.dart         # App-wide constants (spacing, radius, etc.)
│   └── utils/
│       ├── proxy_helper.dart
│       ├── time_utils.dart            # NEW: formatTimeAgo
│       ├── format_utils.dart          # NEW: formatCount, etc.
│       ├── navigation_utils.dart      # NEW: navigateToProfile, etc.
│       └── location_service.dart
│
├── models/                            # Data models (unchanged)
│   ├── post.dart
│   ├── user_profile.dart
│   ├── comment.dart
│   ├── chat_message.dart
│   ├── notification.dart
│   └── signup_data.dart
│
├── services/                          # Business logic / data access
│   ├── auth_service.dart
│   ├── post_service.dart              # Extracted from firestore_service
│   ├── user_service.dart              # Extracted from firestore_service
│   ├── social_service.dart            # Extracted from firestore_service (follow/like)
│   ├── comment_service.dart           # Extracted from firestore_service
│   ├── feed_service.dart              # Extracted from firestore_service
│   ├── chat_service.dart              # Extracted from firestore_service
│   ├── notification_service.dart
│   ├── search_service.dart            # Extracted from firestore_service
│   ├── media_upload_service.dart
│   ├── backend_service.dart
│   ├── otp_service.dart
│   ├── r2_service.dart
│   └── geocoding_service.dart
│
├── shared/                            # Reusable UI components
│   └── widgets/
│       ├── user_avatar.dart           # NEW
│       ├── post_card.dart             # UNIFIED single post card
│       ├── event_post_card.dart       # Renamed + refactored (uses shared components)
│       ├── post_actions.dart          # NEW: Like, comment, share row
│       ├── like_button.dart           # NEW
│       ├── follow_button.dart         # NEW
│       ├── post_author_header.dart    # NEW
│       ├── post_media_display.dart    # NEW
│       ├── time_ago_text.dart         # NEW
│       ├── empty_state.dart           # NEW
│       ├── shimmer_loading.dart       # Extracted
│       ├── action_button.dart         # NEW
│       ├── input_field.dart           # Moved from widgets/
│       ├── primary_button.dart        # Moved from widgets/
│       ├── bottom_nav_bar.dart        # Moved from widgets/
│       ├── user_search_card.dart      # Moved from widgets/
│       └── video_slider.dart          # Moved from widgets/
│
├── features/                          # Feature screens organized by domain
│   ├── auth/
│   │   ├── welcome_screen.dart        # Slimmed down
│   │   ├── login_page.dart
│   │   ├── verify_email_screen.dart
│   │   └── painters/                  # Extracted from welcome_screen
│   │       ├── wave_painter.dart
│   │       ├── geometric_shapes_painter.dart
│   │       └── loading_ring_painter.dart
│   ├── signup/
│   │   ├── signup_email.dart
│   │   ├── signup_otp.dart
│   │   ├── signup_password.dart
│   │   ├── signup_personal.dart
│   │   ├── signup_username.dart
│   │   ├── signup_dob.dart
│   │   ├── signup_location.dart
│   │   └── signup_profile.dart
│   ├── home/
│   │   ├── home_screen.dart           # Slimmed: removed embedded PostCard
│   │   └── main_navigation_screen.dart
│   ├── feed/
│   │   ├── feed_screen.dart
│   │   ├── recommended_feed_list.dart # Extracted from feed_screen
│   │   └── paginated_feed_list.dart   # Extracted from feed_screen
│   ├── post/
│   │   ├── new_post_screen.dart
│   │   ├── post_detail_screen.dart
│   │   └── post_type_selector_sheet.dart
│   ├── profile/
│   │   ├── personal_account.dart
│   │   └── edit_profile.dart
│   ├── search/
│   │   └── search_screen.dart
│   ├── reels/
│   │   ├── reels_feed_screen.dart
│   │   └── reel_post_item.dart        # Extracted from reels_feed_screen
│   ├── events/
│   │   └── create_event_screen.dart
│   ├── community/
│   │   └── community_screen.dart
│   ├── activity/
│   │   └── activity_screen.dart
│   ├── chat/
│   │   └── group_chat_screen.dart
│   ├── video/
│   │   └── video_player_screen.dart
│   └── onboarding/
│       └── interest_picker_screen.dart
│
└── (old folders removed after migration)
```

---

## 6. Phased Refactor Roadmap

### Phase 1: Quick Wins — Extract Shared Utilities (Risk: LOW ✅)
**Goal**: Remove copy-pasted utility functions without touching any UI.

| Step | Action | Files Affected | Risk |
|---|---|---|---|
| 1.1 | Create `core/utils/time_utils.dart` with `formatTimeAgo()` | New file | None |
| 1.2 | Replace `_formatTimeAgo()` in `post_card.dart`, `home_screen.dart` with import | 2 files | Very Low |
| 1.3 | Create `core/utils/navigation_utils.dart` with `navigateToProfile()` | New file | None |
| 1.4 | Replace `_navigateToUserProfile()` in 4 files with import | 4 files | Very Low |
| 1.5 | Create `core/utils/format_utils.dart` with `formatCount()` | New file | None |
| 1.6 | Fix filename: `Event post card.dart` → `event_post_card.dart` | 1 file + imports | Low |
| 1.7 | Fix filename: `PostTypeSelectorSheet.dart` → `post_type_selector_sheet.dart` | 1 file + imports | Low |

**Validation**: Run `flutter analyze` + `flutter test` after each step.

---

### Phase 2: Extract Reusable Widgets (Risk: LOW-MEDIUM ⚠️)
**Goal**: Create shared widgets and use them in one place at a time.

| Step | Action | Details |
|---|---|---|
| 2.1 | Create `shared/widgets/user_avatar.dart` | `CircleAvatar` + network image + initials fallback + `ProxyHelper` |
| 2.2 | Replace `CircleAvatar` blocks one-by-one | Start with `personal_account.dart`, then `post_card.dart`, etc. |
| 2.3 | Create `shared/widgets/like_button.dart` | Optimistic like toggle with `StreamBuilder`, wraps `BackendService.toggleLike` |
| 2.4 | Replace inline like logic in `PostCard` first | Then `ModernPostCard`, then `PostDetailScreen` |
| 2.5 | Create `shared/widgets/post_author_header.dart` | Avatar + Name + Time + More button + onTap navigation |
| 2.6 | Create `shared/widgets/empty_state.dart` | Configurable with icon, title, subtitle, action button |
| 2.7 | Create `shared/widgets/shimmer_loading.dart` | Extract from `post_card.dart` |
| 2.8 | Create `shared/widgets/post_media_display.dart` | Unified image/video display |

**Migration approach**: For each widget:
1. Create the shared widget
2. Use it in **one** screen
3. Verify app works
4. Expand to next screen
5. Repeat

---

### Phase 3: Unify Theme System (Risk: MEDIUM ⚠️)
**Goal**: Single source of truth for colors, typography, spacing.

| Step | Action |
|---|---|
| 3.1 | Audit all hardcoded colors across all files (e.g., `Color(0xFF2563EB)` appears in 6+ files) |
| 3.2 | Merge `config/app_colors.dart`, `config/app_typography.dart`, `config/app_theme.dart`, `theme/app_theme.dart` into `core/theme/` |
| 3.3 | Update `main.dart` to use the unified `AppTheme.lightTheme` instead of inline `ThemeData` |
| 3.4 | Replace hardcoded `Color(0xFF...)` values with `AppColors.xxx` references, file by file |
| 3.5 | Replace inline `TextStyle(fontFamily: 'Inter', ...)` with `AppTypography.xxx` references |
| 3.6 | Delete old `theme/app_theme.dart` (the 81-line duplicate) |

---

### Phase 4: Reduce Post Card Variants (Risk: MEDIUM ⚠️)
**Goal**: Go from 4 post cards → 1 unified `PostCard` + 1 `EventPostCard`.

| Step | Action |
|---|---|
| 4.1 | Compare `PostCard` and `ModernPostCard` — identify layout differences |
| 4.2 | Add a `PostCardVariant` enum (`standard`, `compact`, `modern`) to `PostCard` |
| 4.3 | Migrate `ModernPostCard` consumers to use `PostCard(variant: PostCardVariant.modern)` |
| 4.4 | Delete `widgets/modern_post_card.dart` |
| 4.5 | Extract `NextdoorStylePostCard` from `home_screen.dart` into its own file |
| 4.6 | Either merge into unified `PostCard` or keep as a thin wrapper using shared sub-widgets |
| 4.7 | Refactor `EventPostCard` to reuse `PostAuthorHeader`, `PostActions`, `UserAvatar` |

---

### Phase 5: Split God-Class `FirestoreService` (Risk: MEDIUM ⚠️)
**Goal**: Go from 1 file with 42 methods → 6-7 focused service files.

| New Service | Methods to Move |
|---|---|
| `post_service.dart` | `createPost`, `deletePost`, `postsByAuthor`, `postsByScope`, `getPostsPaginated`, `postsForFeed`, `_postsFromQuerySnapshot` |
| `user_service.dart` | `userProfileStream`, `getUserProfile`, `createUserProfile`, `updateUserProfile`, `syncGoogleUser`, `incrementContentCount`, `recalculateUserStats`, `searchUsers` |
| `social_service.dart` | `followUser`, `unfollowUser`, `followersStream`, `isUserFollowedStream`, `toggleLikePost`, `setPostLike`, `isPostLikedStream`, `likedPostsStream` |
| `comment_service.dart` | `commentsStream`, `addComment` |
| `feed_service.dart` | `getRecommendedFeed`, `addWithFairness`, `logUserActivity` |
| `search_service.dart` | `searchUsers`, `searchPosts` |
| `chat_service.dart` | `messagesStream`, `sendChatMessage` |
| `notification_service_firestore.dart` | `createNotification`, `notificationsStream`, `joinedEventsStream` |

**Migration approach**:
1. Create new service file with methods moved
2. Have `FirestoreService.oldMethod()` delegate to new service (thin wrapper)
3. Update consumers one by one
4. Remove delegating wrappers from `FirestoreService`

---

### Phase 6: Decompose Large Screens (Risk: LOW ✅)
**Goal**: Break 800+ line screens into focused components.

| Screen | Action |
|---|---|
| `welcome_screen.dart` (1,475 lines) | Extract `WavePainter`, `GeometricShapesPainter`, `LoadingRingPainter` → `features/auth/painters/`. Extract login form into `LoginForm` widget. |
| `home_screen.dart` (810 lines) | Extract `NextdoorStylePostCard` → own file. Extract `_buildPostList` → `HomeFeedList` widget. |
| `feed_screen.dart` (701 lines) | Extract `RecommendedFeedList` and `PaginatedFeedList` → own files in `features/feed/`. |
| `reels_feed_screen.dart` (747 lines) | Extract `ReelPostItem` → `features/reels/reel_post_item.dart`. |
| `post_detail_screen.dart` (829 lines) | Extract `_buildCommentsList` → `CommentList` widget. Extract `_buildCommentInput` → `CommentInput` widget. |

---

### Phase 7: Reorganize Into Feature Folders (Risk: LOW ✅)
**Goal**: Move files into the `features/` and `core/` structure.

This is purely file moves + import updates. Do it last when everything is stable.

| Step | Action |
|---|---|
| 7.1 | Create final directory structure under `features/`, `core/`, `shared/` |
| 7.2 | Move files one feature at a time |
| 7.3 | Update imports (use IDE refactoring tools) |
| 7.4 | Delete empty old directories |

---

### Phase 8: Cleanup (Risk: VERY LOW ✅)

| Step | Action |
|---|---|
| 8.1 | Remove `widgets/premium_components.dart` if unused |
| 8.2 | Clear any TODO/dead code |
| 8.3 | Run `dart fix --apply` |
| 8.4 | Run `flutter analyze` — zero warnings target |
| 8.5 | Update barrel exports if needed |

---

## 7. Risk Mitigation Strategy

### General Rules
1. **One file at a time** — Never refactor more than one file between testing
2. **`flutter analyze` after every change** — Must pass before moving forward
3. **Hot restart after every UI change** — Visual regression check
4. **Git commit after each step** — Atomic, revertable commits
5. **Branch per phase** — `refactor/phase-1-utils`, `refactor/phase-2-widgets`, etc.

### Risk Matrix

| Phase | Risk Level | Rollback Strategy |
|---|---|---|
| Phase 1: Extract utils | 🟢 Very Low | Revert commit |
| Phase 2: Extract widgets | 🟡 Low-Medium | Widget-by-widget revert |
| Phase 3: Unify theme | 🟡 Medium | Color/style changes are visual — screenshot compare |
| Phase 4: Unify post cards | 🟡 Medium | Keep old widgets until new one is verified in all contexts |
| Phase 5: Split services | 🟡 Medium | Delegation pattern means old API still works |
| Phase 6: Decompose screens | 🟢 Low | Pure extraction, no logic changes |
| Phase 7: Reorganize folders | 🟢 Low | IDE rename/move handles imports |
| Phase 8: Cleanup | 🟢 Very Low | `dart fix` is reversible |

### What NOT to Do
- ❌ Don't introduce state management (Bloc/Riverpod) during this refactor
- ❌ Don't change any external API or Firebase structure
- ❌ Don't merge phases — complete one fully before starting the next
- ❌ Don't delete any file until its replacement is fully tested
- ❌ Don't refactor and add features simultaneously

---

## 8. Priority Order (Recommended)

If you want maximum impact with minimum risk, start here:

| Priority | Phase | Impact | Effort |
|---|---|---|---|
| 🥇 | **Phase 1**: Extract utils | Removes 200+ duplicated lines | 1–2 hours |
| 🥈 | **Phase 3**: Unify theme | Fixes the biggest consistency problem | 2–3 hours |
| 🥉 | **Phase 2**: Extract shared widgets | Biggest line-count reduction (~1,500 lines) | 4–6 hours |
| 4th | **Phase 6**: Decompose large screens | Makes code maintainable | 3–4 hours |
| 5th | **Phase 4**: Unify post cards | Eliminates the worst duplication | 3–4 hours |
| 6th | **Phase 5**: Split services | Makes testing possible | 2–3 hours |
| 7th | **Phase 7**: Reorganize folders | Clean structure | 1–2 hours |
| 8th | **Phase 8**: Cleanup | Polish | 1 hour |

**Total estimated effort: 17–25 hours of incremental work.**

---

## 9. Dependency Graph (Current — issues highlighted)

```
                    main.dart
                       │
                    HomeScreen ──────────────┐
                    │        │               │
             FeedScreen   PersonalAccount  SearchScreen
                │              │              │
        ┌───────┴──────┐   PostCard        ModernPostCard
        │              │      │               │
   PaginatedFeedList   │   EventPostCard    ProxyHelper
        │              │      │
    ModernPostCard  RecommendedFeedList
        │
    ProxyHelper

    ⚠️ PostCard imports EventPostCard (screens/ → widgets cross-dependency)
    ⚠️ ModernPostCard imports PersonalAccount (widget → screen dependency)
    ⚠️ NextdoorStylePostCard is INSIDE home_screen.dart
```

After refactoring, the dependency flow should be strictly:
```
features/ → shared/widgets/ → core/ → models/
features/ → services/ → models/
shared/ → core/ → models/
```

No widget should import a screen. No screen should contain embedded widget classes.

---

## 10. Summary

| Category | Before | After (Target) |
|---|---|---|
| Post card variants | 4 separate implementations | 1 unified + 1 event |
| Theme sources | 4 conflicting files + inline | 1 unified system |
| `_formatTimeAgo()` copies | 3 | 1 shared utility |
| `_navigateToUserProfile()` copies | 4 | 1 shared utility |
| Like toggle implementations | 4 | 1 shared widget |
| CircleAvatar+fallback | 11 files | 1 `UserAvatar` widget |
| `FirestoreService` methods | 42 in 1 file | Split across 7 focused services |
| Max file length | 1,475 lines | Target < 400 lines |
| Circular dependencies | 3+ | 0 |

---

*Ready to start? I recommend beginning with **Phase 1** — it's the safest, quickest win and will immediately improve code quality.*
