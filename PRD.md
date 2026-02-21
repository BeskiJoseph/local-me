# Product Requirement Document (PRD): ZenFlow (Project TestPro)

## 1. Executive Summary
ZenFlow is a high-performance, community-centric social platform designed to bridge the gap between digital interaction and real-world local engagement. It allows users to discover nearby events, read long-form articles, and connect with local creators through a personalized, location-aware feed.

---

## 2. Project Goals
- **Foster Local Community**: Providing tools for local event discovery and organization.
- **Premium User Experience**: Delivering a "Threads-inspired" aesthetic with smooth animations and optimistic UI updates.
- **Intelligent Discovery**: Utilizing a sophisticated recommendation engine (V3) that balances user interests, geographical proximity, and content freshness.
- **Creator Empowerment**: Offering robust tools for writing articles and managing event attendance.

---

## 3. Target Audience
- **Local Residents**: People looking for community events and locally relevant news.
- **Thought Leaders/Creators**: Individuals sharing long-form content (Articles) with a local or global reach.
- **Event Organizers**: Users hosting physical or digital gatherings.

---

## 4. Functional Requirements

### 4.1 Onboarding & Authentication
- **Multi-channel Login**: Support for Email/Password, OTP (One-Time Password) via Cloud Functions, and Google Sign-In.
- **Registration Flow**: 2-step process involving account creation and profile setup (displayName, bio, profile image).
- **Safety**: 1-minute "cooling period" for new accounts before posting to prevent spam.

### 4.2 Discovery Engine (Feed)
- **Geographical Scoping**: 
  - **Nearby Feed**: Prioritizes content within the user's city/region.
  - **Global Feed**: Broad discovery from the entire platform.
- **Recommendation System (V3)**: 
  - Scoring based on weights: Watch Time, Likes, Comments, Shares.
  - Negative signals (skips) to penalize irrelevant content.
  - Session-level personalization for "sticky" engagement.
- **Optimistic Updates**: Immediate UI response for "Like" and "Going" actions.

### 4.3 Content Creation
- **Articles**: Rich-text support for titles and bodies, image uploads, and location tagging.
- **Events**: 
  - Fields: Title, Description, Type (Classic/Digital), Date/Time, Physical Location.
  - Support for media covers.
  - Latitude/Longitude capturing for map-based discovery.
- **Media Pipeline**: Client-side compression before uploading to Cloudflare R2 via a Node.js proxy.

### 4.4 Social & Community
- **Interactions**: Liking, following, and multi-level commenting.
- **Community Tab**: Dedicated hub for event listing with real-time attendee counts.
- **Event Management**: "Going" status tracking and event-specific chat rooms.

### 4.5 Profile Management
- **Personal Brand**: Dark-mode profile cards, verified badges, and horizontal follower/following stats.
- **Content History**: Tabbed interface showing "Posts", "Replies", and "Joined Events".

---

## 5. Non-Functional Requirements
- **Performance**: <200ms perceived latency for actions using optimistic UI.
- **Scalability**: Backend structured to handle high-concurrency feed fetches via paginated API routes.
- **Security**: 
  - JWT/Firebase Token verification for all API requests.
  - Audit logging for administrative actions.
  - Role-based access control (Admin/Moderator/User).
- **Resilience**: Optional location capturing (app continues working if GPS/Perms are unavailable).

---

## 6. Technical Architecture
- **Frontend**: Flutter (iOS, Android, Web).
- **Backend**: Node.js / Express (Deployed as microservices).
- **Database**: Firestore (Primary storage).
- **Storage**: Cloudflare R2 (Media storage with CORS-compliant proxy).
- **Auth**: Firebase Authentication.
- **RecSys**: Custom TypeScript/Node engine with negative feedback loops.

---

## 7. UI/UX Philosophy
- **Rich Aesthetics**: Vibrant gradients, glassmorphism elements, and modern typography (Outfit/Inter).
- **Micro-animations**: Subtle transitions for feed loading and button interactions.
- **Contextual Search**: Persistent search bars in community hubs with category-based filtering pills.
