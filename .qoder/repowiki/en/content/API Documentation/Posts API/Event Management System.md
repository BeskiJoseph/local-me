# Event Management System

<cite>
**Referenced Files in This Document**
- [posts.js](file://backend/src/routes/posts.js)
- [interactions.js](file://backend/src/routes/interactions.js)
- [app.js](file://backend/src/app.js)
- [firebase.js](file://backend/src/config/firebase.js)
- [post.dart](file://testpro-main/lib/models/post.dart)
- [event_group.dart](file://testpro-main/lib/models/event_group.dart)
- [event_group_member.dart](file://testpro-main/lib/models/event_group_member.dart)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart)
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
This document describes the event management system integrated with posts. It covers the event creation workflow, automatic group and membership creation, event lifecycle management (status computation, archival), cascade deletion, and the relationships between posts, event groups, members, and attendance tracking. It also documents privacy and visibility controls, and provides practical examples for creating events, managing member roles, and monitoring event status.

## Project Structure
The event management system spans backend API routes and frontend models/services:
- Backend routes define event creation, retrieval, deletion, and attendance/member management.
- Frontend Dart models represent event-related data structures.
- Firebase Admin SDK connects to Firestore for persistence and transactions.

```mermaid
graph TB
subgraph "Backend"
APP["Express App<br/>app.js"]
POSTS["Posts Routes<br/>posts.js"]
INTERACTIONS["Interactions Routes<br/>interactions.js"]
FIREBASE["Firebase Config<br/>firebase.js"]
end
subgraph "Firestore Collections"
POSTS_COL["posts"]
EVENT_GROUPS["event_groups"]
EVENT_MEMBERS["event_group_members"]
EVENT_ATTENDANCE["event_attendance"]
end
subgraph "Frontend"
MODELS["Dart Models<br/>post.dart<br/>event_group.dart<br/>event_group_member.dart"]
SERVICE["Backend Service<br/>backend_service.dart"]
end
APP --> POSTS
APP --> INTERACTIONS
POSTS --> FIREBASE
INTERACTIONS --> FIREBASE
POSTS --> POSTS_COL
POSTS --> EVENT_GROUPS
POSTS --> EVENT_MEMBERS
POSTS --> EVENT_ATTENDANCE
INTERACTIONS --> EVENT_ATTENDANCE
INTERACTIONS --> EVENT_MEMBERS
MODELS --> SERVICE
```

**Diagram sources**
- [app.js](file://backend/src/app.js#L44-L60)
- [posts.js](file://backend/src/routes/posts.js#L62-L207)
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)
- [firebase.js](file://backend/src/config/firebase.js#L27-L44)
- [post.dart](file://testpro-main/lib/models/post.dart#L1-L143)
- [event_group.dart](file://testpro-main/lib/models/event_group.dart#L1-L35)
- [event_group_member.dart](file://testpro-main/lib/models/event_group_member.dart#L1-L35)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L473-L496)

**Section sources**
- [app.js](file://backend/src/app.js#L44-L60)
- [posts.js](file://backend/src/routes/posts.js#L62-L207)
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)
- [firebase.js](file://backend/src/config/firebase.js#L27-L44)

## Core Components
- Event creation endpoint validates inputs, enforces account age, and creates posts with event-specific fields.
- On event creation, backend creates an event group and assigns the creator as admin.
- Event lifecycle: status computed lazily from dates; expired events are treated as archived for display.
- Cascade deletion removes event posts along with associated event groups, members, and attendance records.
- Attendance and membership: joining an event creates entries in both event_attendance and event_group_members collections.
- Visibility: posts can be public or shadow-banned; shadow-banned posts are invisible to non-authors.

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L62-L207)
- [posts.js](file://backend/src/routes/posts.js#L230-L293)
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)
- [posts.js](file://backend/src/routes/posts.js#L607-L656)

## Architecture Overview
The system uses Firestore collections to model events and related entities. The backend ensures atomicity with transactions and maintains referential integrity across posts, event groups, members, and attendance.

```mermaid
sequenceDiagram
participant Client as "Client"
participant Posts as "Posts Route"
participant Tx as "Firestore Transaction"
participant Groups as "event_groups"
participant Members as "event_group_members"
Client->>Posts : POST /api/posts (isEvent=true,<br/>eventStartDate,eventEndDate)
Posts->>Tx : Start transaction
Posts->>Tx : Create post document
alt isEvent is true
Posts->>Tx : Create event_groups document
Posts->>Tx : Create event_group_members document (role=admin)
end
Tx-->>Posts : Commit
Posts-->>Client : 201 Created (post + group + admin member)
```

**Diagram sources**
- [posts.js](file://backend/src/routes/posts.js#L62-L207)

## Detailed Component Analysis

### Event Creation Workflow
- Validation: Requires eventStartDate and eventEndDate when isEvent is true; endDate must be after startDate.
- Account age: Minimum 1 minute required since registration.
- Shadow ban: If user is shadow_banned, post visibility is set to shadow.
- Transaction: Creates post, and if event, creates event_groups and event_group_members with admin role.
- Audit logging and feed cache invalidation occur after successful creation.

```mermaid
flowchart TD
Start(["POST /api/posts"]) --> Validate["Validate payload<br/>and event dates"]
Validate --> AccountAge["Check account age >= 1 min"]
AccountAge --> ShadowCheck["Check shadow ban status"]
ShadowCheck --> TxStart["Start Firestore transaction"]
TxStart --> CreatePost["Create post document"]
CreatePost --> IsEvent{"isEvent?"}
IsEvent --> |Yes| CreateGroup["Create event_groups document"]
CreateGroup --> CreateMember["Create event_group_members (role=admin)"]
IsEvent --> |No| SkipGroup["Skip group/member creation"]
CreateMember --> Commit["Commit transaction"]
SkipGroup --> Commit
Commit --> Audit["Log audit action"]
Audit --> Cache["Invalidate feed cache"]
Cache --> Done(["201 Created"])
```

**Diagram sources**
- [posts.js](file://backend/src/routes/posts.js#L62-L207)

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L62-L207)

### Event Lifecycle Management
- Computation: For feed and single-post retrieval, event status is computed lazily based on eventEndDate compared to current time.
- Archival: Expired events are marked as archived for display purposes; this is computed and not written to the database.
- Visibility: Shadow-banned posts are invisible to non-authors.

```mermaid
flowchart TD
Entry(["Load post/feed"]) --> CheckEvent{"isEvent?"}
CheckEvent --> |No| ReturnActive["Return as active"]
CheckEvent --> |Yes| ParseDates["Parse eventStartDate/endDate"]
ParseDates --> HasEnd{"Has eventEndDate?"}
HasEnd --> |No| ReturnActive
HasEnd --> |Yes| Compare["Compare endDate < now"]
Compare --> |True| MarkArchived["Mark computedStatus=archived"]
Compare --> |False| KeepActive["Keep computedStatus=active"]
MarkArchived --> Return
KeepActive --> Return
ReturnActive --> Return(["Return post/feed item"])
```

**Diagram sources**
- [posts.js](file://backend/src/routes/posts.js#L230-L293)
- [posts.js](file://backend/src/routes/posts.js#L533-L601)

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L230-L293)
- [posts.js](file://backend/src/routes/posts.js#L533-L601)

### Cascade Deletion Handling
- Deletion requires author ownership or admin role.
- Deletes the post and, if event, cascades to event_groups, event_group_members, and event_attendance.

```mermaid
sequenceDiagram
participant Client as "Client"
participant Posts as "Posts Route"
participant Batch as "Firestore Batch"
participant Groups as "event_groups"
participant Members as "event_group_members"
participant Attendance as "event_attendance"
Client->>Posts : DELETE /api/posts/ : id
Posts->>Batch : Initialize batch
Posts->>Batch : Delete post document
alt Post is event
Posts->>Groups : Query by eventId
Groups-->>Posts : Group docs
Posts->>Batch : Delete all group docs
Posts->>Members : Query by eventId
Members-->>Posts : Member docs
Posts->>Batch : Delete all member docs
Posts->>Attendance : Query by eventId
Attendance-->>Posts : Attendance docs
Posts->>Batch : Delete all attendance docs
end
Batch-->>Posts : Commit
Posts-->>Client : 200 OK
```

**Diagram sources**
- [posts.js](file://backend/src/routes/posts.js#L607-L656)

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L607-L656)

### Relationship Between Posts and Event Groups
- Each event post references an event group via eventId.
- The event group stores creatorId and groupStatus.
- Member management mirrors attendance: both use deterministic IDs combining eventId and userId.

```mermaid
erDiagram
POSTS {
string id PK
boolean isEvent
datetime eventStartDate
datetime eventEndDate
string eventLocation
string eventType
boolean isFree
int attendeeCount
}
EVENT_GROUPS {
string id PK
string eventId FK
string creatorId
string groupStatus
}
EVENT_GROUP_MEMBERS {
string id PK
string eventId FK
string userId
string role
datetime joinedAt
}
EVENT_ATTENDANCE {
string id PK
string eventId FK
string userId
datetime createdAt
}
POSTS ||--o{ EVENT_GROUPS : "references"
POSTS ||--o{ EVENT_GROUP_MEMBERS : "references"
POSTS ||--o{ EVENT_ATTENDANCE : "references"
```

**Diagram sources**
- [posts.js](file://backend/src/routes/posts.js#L158-L177)
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)
- [event_group.dart](file://testpro-main/lib/models/event_group.dart#L1-L35)
- [event_group_member.dart](file://testpro-main/lib/models/event_group_member.dart#L1-L35)

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L158-L177)
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)
- [event_group.dart](file://testpro-main/lib/models/event_group.dart#L1-L35)
- [event_group_member.dart](file://testpro-main/lib/models/event_group_member.dart#L1-L35)

### Attendance Tracking and Member Management
- Join/Leave: Uses deterministic IDs combining eventId and userId for both event_attendance and event_group_members.
- Safety: Prevents joining expired events; decrements attendeeCount on leave.
- Queries: Dedicated endpoints to check attendance and retrieve joined event IDs.

```mermaid
sequenceDiagram
participant Client as "Client"
participant Interactions as "Interactions Route"
participant Tx as "Firestore Transaction"
participant Post as "posts"
participant Attendance as "event_attendance"
participant Members as "event_group_members"
Client->>Interactions : POST /api/interactions/event/join (eventId)
Interactions->>Tx : Start transaction
Interactions->>Post : Load post (eventId)
Interactions->>Tx : Check endDate < now
alt Already attending
Interactions->>Tx : Delete attendance doc
Interactions->>Tx : Delete member doc
Interactions->>Post : Decrement attendeeCount
else Not attending
Interactions->>Tx : Create attendance doc
Interactions->>Tx : Create member doc (role=member)
Interactions->>Post : Increment attendeeCount
end
Tx-->>Interactions : Commit
Interactions-->>Client : 200 OK
```

**Diagram sources**
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)

**Section sources**
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)
- [interactions.js](file://backend/src/routes/interactions.js#L477-L494)
- [interactions.js](file://backend/src/routes/interactions.js#L497-L518)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L473-L496)

### Privacy and Visibility Controls
- Shadow ban: Posts by shadow_banned users are marked shadow and invisible to non-authors.
- Single post retrieval enforces a stealth 404 for shadow posts when accessed by non-authors.
- Feed filtering: Only public, active posts are returned by default.

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L123-L147)
- [posts.js](file://backend/src/routes/posts.js#L544-L549)
- [posts.js](file://backend/src/routes/posts.js#L392-L446)

## Dependency Analysis
- Routing: Protected routes are mounted under /api with authentication and rate limiting.
- Authentication: Middleware injects req.user with uid and role.
- Firestore: Transactions and batch writes ensure consistency across posts and event collections.
- Frontend models: Dart models mirror backend event fields and statuses for UI consumption.

```mermaid
graph LR
AUTH["auth.js"] --> APP["app.js"]
RATE["progressiveLimiter.js"] --> APP
APP --> POSTS["posts.js"]
APP --> INTERACTIONS["interactions.js"]
POSTS --> FIREBASE["firebase.js"]
INTERACTIONS --> FIREBASE
MODELS["post.dart<br/>event_group.dart<br/>event_group_member.dart"] --> SERVICE["backend_service.dart"]
```

**Diagram sources**
- [app.js](file://backend/src/app.js#L44-L60)
- [posts.js](file://backend/src/routes/posts.js#L62-L207)
- [interactions.js](file://backend/src/routes/interactions.js#L248-L322)
- [firebase.js](file://backend/src/config/firebase.js#L27-L44)
- [post.dart](file://testpro-main/lib/models/post.dart#L1-L143)
- [event_group.dart](file://testpro-main/lib/models/event_group.dart#L1-L35)
- [event_group_member.dart](file://testpro-main/lib/models/event_group_member.dart#L1-L35)
- [backend_service.dart](file://testpro-main/lib/services/backend_service.dart#L473-L496)

**Section sources**
- [app.js](file://backend/src/app.js#L44-L60)
- [firebase.js](file://backend/src/config/firebase.js#L27-L44)

## Performance Considerations
- Feed caching: In-memory cache with TTL reduces repeated queries for regional feeds.
- Fetch locks: Prevent dog-piling during concurrent regional feed requests.
- Index-aware queries: Missing composite indexes produce explicit errors to guide index creation.
- Anti-scraping jitter: Random delay on initial feed loads to deter scraping.

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L209-L212)
- [posts.js](file://backend/src/routes/posts.js#L353-L359)
- [posts.js](file://backend/src/routes/posts.js#L466-L477)
- [posts.js](file://backend/src/routes/posts.js#L515-L521)

## Troubleshooting Guide
- Event creation errors:
  - Missing event dates when isEvent is true.
  - Invalid date range (endDate must be after startDate).
  - Account too new (< 1 minute).
- Deletion errors:
  - Unauthorized if not author or admin.
  - Cascading deletes require proper indexing for event collections.
- Attendance errors:
  - Cannot join expired events.
  - Deterministic ID collisions avoided by using eventId_userid pattern.
- Visibility:
  - Shadow-banned posts appear as not found to non-authors.

**Section sources**
- [posts.js](file://backend/src/routes/posts.js#L82-L95)
- [posts.js](file://backend/src/routes/posts.js#L114-L119)
- [posts.js](file://backend/src/routes/posts.js#L615-L617)
- [interactions.js](file://backend/src/routes/interactions.js#L279-L283)
- [posts.js](file://backend/src/routes/posts.js#L544-L549)

## Conclusion
The event management system integrates tightly with posts, ensuring atomic creation of event groups and admin assignments. Lifecycle management is computed lazily for performance, while cascade deletion maintains referential integrity. Privacy controls respect shadow bans, and the frontend models align with backend structures for consistent UI behavior. The documented APIs and flows provide a clear blueprint for extending or integrating event features.