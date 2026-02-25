# Real-time Features

<cite>
**Referenced Files in This Document**
- [main.dart](file://testpro-main/lib/main.dart)
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart)
- [notification_data_service.dart](file://testpro-main/lib/services/notification_data_service.dart)
- [notification.dart](file://testpro-main/lib/models/notification.dart)
- [chat_service.dart](file://testpro-main/lib/services/chat_service.dart)
- [chat_message.dart](file://testpro-main/lib/models/chat_message.dart)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js)
- [google-services.json](file://testpro-main/android/app/google-services.json)
- [AppDelegate.swift](file://testpro-main/ios/Runner/AppDelegate.swift)
- [index.js](file://testpro-main/functions/index.js)
- [notifications.js](file://backend/src/routes/notifications.js)
- [feed_repository.dart](file://testpro-main/lib/repositories/feed_repository.dart)
- [user_repository.dart](file://testpro-main/lib/repositories/user_repository.dart)
- [post.dart](file://testpro-main/lib/models/post.dart)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Conclusion](#conclusion)

## Introduction
This document explains the real-time communication features implemented in the project. It covers:
- Firebase Cloud Messaging (FCM) integration for push notifications, including setup, foreground/background handling, and token lifecycle.
- Firestore-related triggers and counters managed by Cloud Functions for derived metrics.
- Local notification handling, channels, and user preference management.
- Near-real-time chat streams using periodic polling against backend APIs.
- Notification retrieval and state updates via backend endpoints.
- Offline capabilities, message queuing, and connection resilience strategies.

## Project Structure
The real-time features span three layers:
- Frontend (Flutter): Initializes Firebase, registers FCM handlers, displays local notifications, and manages periodic streams for chat and notifications.
- Backend (Express): Provides REST endpoints for notifications and interacts with Firestore.
- Cloud Functions (Node.js): Implements Firestore triggers to maintain counters and derive metrics.

```mermaid
graph TB
subgraph "Frontend (Flutter)"
A_Main["main.dart<br/>Initialize Firebase and NotificationService"]
A_NotifSvc["notification_service.dart<br/>FCM + Local Notifications"]
A_NotifDS["notification_data_service.dart<br/>Poll notifications"]
A_ChatSvc["chat_service.dart<br/>Poll messages"]
A_Backend["backend_service.dart<br/>HTTP client facade"]
end
subgraph "Backend (Express)"
B_Routes["notifications.js<br/>GET /api/notifications<br/>PATCH /api/notifications/:id/read"]
end
subgraph "Cloud Functions (Node.js)"
C_Functions["index.js<br/>Firestore triggers for counters"]
end
subgraph "Web (Service Worker)"
W_SW["firebase-messaging-sw.js<br/>Background FCM handling"]
end
A_Main --> A_NotifSvc
A_NotifSvc --> A_Backend
A_NotifDS --> A_Backend
A_ChatSvc --> A_Backend
A_Backend --> B_Routes
B_Routes --> C_Functions
A_NotifSvc --> W_SW
```

**Diagram sources**
- [main.dart](file://testpro-main/lib/main.dart#L12-L22)
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L57)
- [notification_data_service.dart](file://testpro-main/lib/services/notification_data_service.dart#L7-L12)
- [chat_service.dart](file://testpro-main/lib/services/chat_service.dart#L8-L16)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L56-L57)
- [notifications.js](file://backend/src/routes/notifications.js#L11-L29)
- [index.js](file://testpro-main/functions/index.js#L13-L34)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L15-L24)

**Section sources**
- [main.dart](file://testpro-main/lib/main.dart#L12-L22)
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L57)
- [notification_data_service.dart](file://testpro-main/lib/services/notification_data_service.dart#L7-L12)
- [chat_service.dart](file://testpro-main/lib/services/chat_service.dart#L8-L16)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L56-L57)
- [notifications.js](file://backend/src/routes/notifications.js#L11-L29)
- [index.js](file://testpro-main/functions/index.js#L13-L34)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L15-L24)

## Core Components
- FCM initialization and token lifecycle: Permission request, token retrieval, token refresh callback, and background message handler registration.
- Local notification display: Foreground message handling and local notification rendering with a high-importance channel.
- Notification data service: Periodic polling of activity notifications from backend endpoints.
- Chat service: Immediate emission plus periodic polling for near-real-time chat.
- Backend service: Centralized HTTP client with token orchestration and endpoint proxies.
- Cloud Functions: Firestore triggers to increment/decrement counters and maintain derived metrics.

**Section sources**
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L92)
- [notification_data_service.dart](file://testpro-main/lib/services/notification_data_service.dart#L7-L25)
- [chat_service.dart](file://testpro-main/lib/services/chat_service.dart#L8-L34)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L70-L497)
- [index.js](file://testpro-main/functions/index.js#L13-L80)

## Architecture Overview
The system integrates Firebase for push notifications and Express endpoints for activity notifications. Firestore triggers keep counters consistent. The frontend initializes FCM, handles foreground/background messages, and polls for chat and notifications.

```mermaid
sequenceDiagram
participant Client as "Flutter App"
participant FCM as "FirebaseMessaging"
participant SW as "firebase-messaging-sw.js"
participant Local as "FlutterLocalNotifications"
participant BE as "Backend (Express)"
participant CF as "Cloud Functions"
Client->>FCM : "initialize(), requestPermission()"
FCM-->>Client : "token"
Client->>BE : "PATCH /api/profiles/me { fcmToken }"
FCM-->>Client : "onMessage"
Client->>Local : "show(title, body)"
note over Client,SW : "Background message received"
FCM-->>SW : "onBackgroundMessage(payload)"
SW-->>Client : "showNotification(title, body)"
BE-->>CF : "Firestore write (e.g., posts/{id}/likes)"
CF-->>BE : "Derived metric update (e.g., likeCount)"
```

**Diagram sources**
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L57)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L15-L24)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L78-L84)
- [notifications.js](file://backend/src/routes/notifications.js#L11-L29)
- [index.js](file://testpro-main/functions/index.js#L13-L34)

## Detailed Component Analysis

### FCM Integration and Notification Service
- Initialization:
  - Requests notification permissions for Android/iOS.
  - Retrieves initial FCM token and syncs it to backend.
  - Initializes local notification plugin and sets up foreground message listener.
  - Registers a top-level background message handler for release builds.
- Token lifecycle:
  - Handles token refresh events and re-syncs with backend.
- Local notifications:
  - Foreground messages trigger local notification display on a high-importance channel.
- Web background handler:
  - Service worker receives background messages and shows notifications.

```mermaid
sequenceDiagram
participant App as "Flutter App"
participant Notif as "NotificationService"
participant FCM as "FirebaseMessaging"
participant SW as "Service Worker"
participant Local as "Local Notifications"
App->>Notif : "initialize()"
Notif->>FCM : "requestPermission()"
FCM-->>Notif : "settings"
Notif->>FCM : "getToken()"
FCM-->>Notif : "token"
Notif->>App : "updateProfile({fcmToken})"
Notif->>Local : "initialize()"
FCM-->>Notif : "onMessage"
Notif->>Local : "show(title, body)"
FCM-->>Notif : "onTokenRefresh"
Notif->>App : "updateProfile({fcmToken})"
FCM-->>SW : "onBackgroundMessage"
SW-->>App : "showNotification(title, body)"
```

**Diagram sources**
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L92)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L15-L24)

**Section sources**
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L92)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L15-L24)
- [google-services.json](file://testpro-main/android/app/google-services.json#L1-L38)
- [AppDelegate.swift](file://testpro-main/ios/Runner/AppDelegate.swift#L1-L14)

### Notification Data Service and Backend Endpoints
- Notification retrieval:
  - Periodic polling every 5 minutes for activity notifications.
  - Converts JSON payloads to typed models.
- Backend endpoints:
  - GET /api/notifications: returns recent notifications for the current user.
  - PATCH /api/notifications/:id/read: marks a notification as read.
- Mark-as-read actions:
  - Client invokes backend to update read state.

```mermaid
sequenceDiagram
participant UI as "UI"
participant DS as "NotificationDataService"
participant BE as "BackendService"
participant API as "Backend (Express)"
UI->>DS : "notificationsStream(userId)"
DS->>BE : "getNotifications()"
BE->>API : "GET /api/notifications"
API-->>BE : "notifications[]"
BE-->>DS : "ApiResponse<List>"
DS-->>UI : "Stream<List<ActivityNotification>>"
UI->>DS : "markNotificationAsRead(id)"
DS->>BE : "markNotificationAsRead(id)"
BE->>API : "PATCH /api/notifications/ : id/read"
API-->>BE : "{ success : true }"
BE-->>DS : "ApiResponse<bool>"
```

**Diagram sources**
- [notification_data_service.dart](file://testpro-main/lib/services/notification_data_service.dart#L7-L25)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L430-L448)
- [notifications.js](file://backend/src/routes/notifications.js#L11-L48)

**Section sources**
- [notification_data_service.dart](file://testpro-main/lib/services/notification_data_service.dart#L7-L25)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L430-L448)
- [notifications.js](file://backend/src/routes/notifications.js#L11-L48)
- [notification.dart](file://testpro-main/lib/models/notification.dart#L1-L88)

### Chat Service and Streams
- Messages stream:
  - Emits current messages immediately upon subscription.
  - Polls every 2 seconds to approximate near-real-time updates.
- Message sending:
  - Sends via backend endpoint and throws on failure.
- Data model:
  - Strongly-typed chat message with sender info and timestamp.

```mermaid
flowchart TD
Start(["messagesStream(eventId)"]) --> EmitNow["Emit current messages"]
EmitNow --> Wait2["Wait 2 seconds"]
Wait2 --> Fetch["Fetch messages from backend"]
Fetch --> EmitNow
Fetch --> |Error| LogErr["Log error and return empty list"]
LogErr --> Wait2
```

**Diagram sources**
- [chat_service.dart](file://testpro-main/lib/services/chat_service.dart#L8-L16)
- [chat_message.dart](file://testpro-main/lib/models/chat_message.dart#L1-L53)

**Section sources**
- [chat_service.dart](file://testpro-main/lib/services/chat_service.dart#L8-L34)
- [chat_message.dart](file://testpro-main/lib/models/chat_message.dart#L1-L53)

### Firestore Triggers and Derived Metrics
- Triggers:
  - Increment/decrement counters for likes, comments, followers, and posts.
  - Transactions clamp negative counts to zero.
- Impact:
  - Keeps derived metrics consistent without client-side writes.

```mermaid
flowchart TD
A["Firestore Write"] --> B{"Trigger Type"}
B --> |like created| C["Increment likeCount (merge)"]
B --> |like deleted| D["Transaction: max(0, likeCount - 1)"]
B --> |comment created| E["Increment commentCount (merge)"]
B --> |comment deleted| F["Transaction: max(0, commentCount - 1)"]
B --> |follower created| G["Increment subscribers (merge)"]
B --> |follower deleted| H["Transaction: max(0, subscribers - 1)"]
B --> |post created| I["Increment contents (merge)"]
B --> |post deleted| J["Transaction: max(0, contents - 1)"]
```

**Diagram sources**
- [index.js](file://testpro-main/functions/index.js#L13-L109)

**Section sources**
- [index.js](file://testpro-main/functions/index.js#L13-L109)

### Backend Service Orchestration and Token Handling
- Token flow:
  - Attempts custom access/refresh token exchange.
  - Falls back to Firebase ID tokens if custom tokens unavailable.
  - Handles 401/403 by clearing tokens and retrying with Firebase tokens.
- Endpoint proxies:
  - Centralized methods for notifications, posts, comments, likes, follows, events, and search.

```mermaid
sequenceDiagram
participant Client as "BackendService"
participant Custom as "Custom Tokens"
participant Firebase as "Firebase Auth"
participant API as "Backend API"
Client->>Custom : "Use accessToken if present"
alt 401 Unauthorized
Client->>Custom : "Attempt refreshToken"
alt Success
Custom-->>Client : "New accessToken"
Client->>API : "Retry with new token"
else Failure
Client->>Firebase : "getIdToken()"
Firebase-->>Client : "idToken"
Client->>API : "Retry with idToken"
end
else Success
API-->>Client : "Response"
end
```

**Diagram sources**
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L104-L212)

**Section sources**
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L104-L212)

### Data Models for Notifications and Posts
- ActivityNotification:
  - Enumerated type for notification categories.
  - Robust JSON parsing and serialization.
- Post:
  - Comprehensive post model including event fields and counters.
  - Fallback parsing for event dates and optional media.

```mermaid
classDiagram
class ActivityNotification {
+String id
+String fromUserId
+String fromUserName
+String? fromUserProfileImage
+String toUserId
+NotificationType type
+String? postId
+String? postThumbnail
+String? commentText
+DateTime timestamp
+bool isRead
+toJson() Map
+fromJson(json) ActivityNotification
}
class Post {
+String id
+String authorId
+String authorName
+String title
+String body
+String scope
+String? mediaUrl
+String mediaType
+DateTime createdAt
+int likeCount
+int commentCount
+double? latitude
+double? longitude
+String? city
+String? country
+String category
+String? thumbnailUrl
+bool isEvent
+DateTime? eventStartDate
+DateTime? eventEndDate
+String? eventType
+String? computedStatus
+String? eventLocation
+bool? isFree
+int attendeeCount
+bool isLiked
+toJson() Map
+fromJson(json) Post
}
```

**Diagram sources**
- [notification.dart](file://testpro-main/lib/models/notification.dart#L1-L88)
- [post.dart](file://testpro-main/lib/models/post.dart#L1-L143)

**Section sources**
- [notification.dart](file://testpro-main/lib/models/notification.dart#L1-L88)
- [post.dart](file://testpro-main/lib/models/post.dart#L1-L143)

### Conceptual Overview
- Real-time feed and recommendations:
  - Feed retrieval via backend posts endpoint; repository composes recommended feeds.
  - User profile caching with periodic refresh.
- Event-driven architecture:
  - Firestore triggers update counters and derived metrics.
  - Backend endpoints expose notifications and interactions.

```mermaid
graph LR
Repo["FeedRepository"] --> BS["BackendService.getPosts()"]
Repo2["UserRepository"] --> Cache["In-memory profile cache"]
Cache --> BS2["BackendService.getProfile()"]
BS --> BE["Backend (Express)"]
BS2 --> BE
BE --> CF["Cloud Functions (Firestore Triggers)"]
```

**Diagram sources**
- [feed_repository.dart](file://testpro-main/lib/repositories/feed_repository.dart#L9-L25)
- [user_repository.dart](file://testpro-main/lib/repositories/user_repository.dart#L21-L29)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L382-L406)
- [index.js](file://testpro-main/functions/index.js#L83-L109)

**Section sources**
- [feed_repository.dart](file://testpro-main/lib/repositories/feed_repository.dart#L9-L25)
- [user_repository.dart](file://testpro-main/lib/repositories/user_repository.dart#L21-L29)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L382-L406)
- [index.js](file://testpro-main/functions/index.js#L83-L109)

## Dependency Analysis
- Frontend depends on:
  - Firebase Messaging and Local Notifications plugins.
  - BackendService for HTTP operations.
- Backend depends on:
  - Firestore for persistence and counters.
  - Cloud Functions for derived metrics.
- Web service worker depends on:
  - Firebase JS SDK for background message handling.

```mermaid
graph TB
FS["Flutter App"] --> FM["FirebaseMessaging"]
FS --> FLN["FlutterLocalNotifications"]
FS --> BS["BackendService"]
BS --> EXP["Express Routes"]
EXP --> CF["Cloud Functions"]
SW["Service Worker"] --> FM
```

**Diagram sources**
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L57)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L56-L57)
- [notifications.js](file://backend/src/routes/notifications.js#L11-L29)
- [index.js](file://testpro-main/functions/index.js#L1-L10)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L1-L24)

**Section sources**
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L57)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L56-L57)
- [notifications.js](file://backend/src/routes/notifications.js#L11-L29)
- [index.js](file://testpro-main/functions/index.js#L1-L10)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L1-L24)

## Performance Considerations
- Polling cadence:
  - Chat: 2-second intervals to balance freshness and cost.
  - Notifications: 5-minute intervals to reduce request storms.
- Derived metrics:
  - Firestore triggers avoid client-side race conditions and ensure consistency.
- Token orchestration:
  - Deduplicated custom token sync prevents concurrent calls and reduces overhead.
- Caching:
  - User profile cache reduces redundant network calls.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
- FCM token not syncing:
  - Verify permission status and ensure token refresh handler is registered.
  - Confirm backend update endpoint is reachable and authenticated.
- Background notifications not showing:
  - Ensure service worker is deployed and registered.
  - Check notification channel configuration and app-level settings.
- Chat messages not updating:
  - Confirm periodic polling is active and backend endpoint returns data.
  - Inspect error logs for fetch failures.
- Notification read state not updating:
  - Verify PATCH endpoint is called with correct ID and user authorization.
- Derived counters incorrect:
  - Check Firestore triggers for errors and confirm transactions execute.

**Section sources**
- [notification_service.dart](file://testpro-main/lib/services/notification_service.dart#L17-L92)
- [firebase-messaging-sw.js](file://testpro-main/web/firebase-messaging-sw.js#L15-L24)
- [chat_service.dart](file://testpro-main/lib/services/chat_service.dart#L8-L34)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L440-L448)
- [index.js](file://testpro-main/functions/index.js#L13-L34)

## Conclusion
The project implements a robust real-time communication stack:
- FCM handles push notifications with foreground/background processing and token lifecycle management.
- Cloud Functions maintain accurate derived metrics via Firestore triggers.
- Local notifications and periodic polling provide responsive UX for chat and notifications.
- Backend endpoints and token orchestration ensure secure and resilient data access.
- Caching and polling strategies balance performance and consistency across devices.

[No sources needed since this section summarizes without analyzing specific files]