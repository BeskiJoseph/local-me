# Session Continuity Intelligence

<cite>
**Referenced Files in This Document**
- [RiskEngine.js](file://backend/src/services/RiskEngine.js)
- [auth.js](file://backend/src/routes/auth.js)
- [deviceContext.js](file://backend/src/middleware/deviceContext.js)
- [firebase.js](file://backend/src/config/firebase.js)
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
This document describes the Session Continuity Intelligence system responsible for monitoring concurrent refresh races, velocity patterns, and active session limits during refresh token operations. It focuses on the evaluateSessionContinuity method that analyzes up to 15 recent tokens per user to detect suspicious activity patterns and integrates with the broader risk scoring system to make enforcement decisions.

## Project Structure
The session continuity intelligence spans three primary areas:
- Authentication route: Orchestrates refresh token validation and delegates session continuity checks.
- Risk engine: Implements temporal and behavioral session continuity logic and global session containment.
- Device context middleware: Normalizes and hashes client identifiers to preserve privacy while enabling correlation.

```mermaid
graph TB
subgraph "Authentication Layer"
R["Routes: auth.js<br/>POST /api/auth/refresh"]
end
subgraph "Intelligence Layer"
D["Middleware: deviceContext.js<br/>Hashes IP/UA/Device"]
S["Service: RiskEngine.js<br/>evaluateSessionContinuity()"]
end
subgraph "Data Layer"
F["Config: firebase.js<br/>Firestore client"]
RT["Collection: refresh_tokens<br/>Stored refresh tokens"]
U["Collection: users<br/>User token version"]
end
R --> D
R --> S
S --> F
F --> RT
F --> U
```

**Diagram sources**
- [auth.js](file://backend/src/routes/auth.js#L166-L280)
- [deviceContext.js](file://backend/src/middleware/deviceContext.js#L1-L24)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L130)
- [firebase.js](file://backend/src/config/firebase.js#L41-L46)

**Section sources**
- [auth.js](file://backend/src/routes/auth.js#L166-L280)
- [deviceContext.js](file://backend/src/middleware/deviceContext.js#L1-L24)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L130)
- [firebase.js](file://backend/src/config/firebase.js#L41-L46)

## Core Components
- evaluateSessionContinuity(userId, currentIpHash): Analyzes up to 15 recent refresh tokens for a user to compute:
  - Active session count (revocation filter)
  - Recent refresh frequency within 1 minute
  - Concurrent refresh race within 3 seconds with differing IP
  - Returns either a hard burn action or an additional risk contribution for broader scoring
- Integration points:
  - Called during refresh after strict device validation
  - Combined with refresh risk and decayed risk to decide soft lock or full burn
  - Triggers global session burn when a hard-burn condition is met

Key behaviors:
- Velocity calculations: Count refresh events within 60 seconds and 3 seconds windows.
- Session counting logic: Increment active sessions for non-revoked tokens.
- IP hash tracking: Capture the IP hash of the most recent prior refresh within the 3-second window to detect concurrent race conditions.

**Section sources**
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L130)
- [auth.js](file://backend/src/routes/auth.js#L209-L214)

## Architecture Overview
The refresh flow integrates session continuity intelligence with broader risk scoring and enforcement.

```mermaid
sequenceDiagram
participant Client as "Client"
participant Route as "Routes : auth.js"
participant Dev as "Middleware : deviceContext.js"
participant Eng as "Service : RiskEngine.js"
participant DB as "Firestore : firebase.js"
Client->>Route : POST /api/auth/refresh {refreshToken}
Route->>Dev : deviceContext()
Dev-->>Route : {ipHash, userAgentHash, deviceIdHash}
Route->>Eng : evaluateSessionContinuity(userId, ipHash)
Eng->>DB : Query refresh_tokens (userId, limit=15)
DB-->>Eng : Snapshot of recent tokens
Eng-->>Route : {action, additionalRisk}
alt action == "hard_burn"
Route->>Eng : executeFullSessionBurn(userId, reason)
Eng->>DB : Batch revoke tokens + bump tokenVersion
DB-->>Eng : Ack
Route-->>Client : 401 Session compromised
else action == "ok"
Route->>Eng : calculateDecayedRisk(tokenData)
Route->>Eng : evaluateRefreshRisk(tokenData, deviceContext)
Route->>Route : cumulativeRisk = decayed + risk + additionalRisk
alt cumulativeRisk >= threshold_hard
Route->>Eng : executeFullSessionBurn(userId, reason)
Route-->>Client : 401 Session compromised
else cumulativeRisk >= threshold_soft
Route-->>Client : 401 Re-authenticate
else
Route-->>Client : New token pair
end
end
```

**Diagram sources**
- [auth.js](file://backend/src/routes/auth.js#L166-L280)
- [deviceContext.js](file://backend/src/middleware/deviceContext.js#L1-L24)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L168)
- [firebase.js](file://backend/src/config/firebase.js#L41-L46)

## Detailed Component Analysis

### evaluateSessionContinuity Method
Purpose:
- Detect concurrent refresh race conditions (different IP within 3 seconds)
- Identify token refresh storms (frequency abuse with 5+ refreshes per minute)
- Enforce active session caps (>10 active sessions)

Processing logic:
- Fetches up to 15 most recent refresh tokens for the user ordered by creation time.
- Iterates tokens to:
  - Count active sessions (non-revoked)
  - Count refreshes within the last 60 seconds
  - Count refreshes within the last 3 seconds and capture the IP hash of the most recent prior refresh
- Decision flow:
  - If any 3-second refresh exists and the captured IP differs from the current IP, trigger a hard burn.
  - Otherwise, compute additional risk:
    - 30 points if 5+ refreshes occurred within the last minute
    - 20 points if active sessions exceed 10
  - Return action "ok" with additional risk for downstream scoring.

```mermaid
flowchart TD
Start(["Entry: evaluateSessionContinuity(userId, currentIpHash)"]) --> Query["Query up to 15 recent tokens for userId"]
Query --> Init["Initialize counters:<br/>activeSessionsCount=0<br/>refreshesLastMinute=0<br/>refreshesLast3Seconds=0<br/>lastRefreshIpHash=null"]
Init --> Loop{"For each token"}
Loop --> Active{"!isRevoked?"}
Active --> |Yes| IncActive["Increment activeSessionsCount"]
Active --> |No| SkipActive["Skip"]
IncActive --> Age["Compute ageMs = now - createdAt"]
SkipActive --> Age
Age --> Minute["ageMs <= 60s?"]
Minute --> |Yes| IncMin["Increment refreshesLastMinute"]
Minute --> |No| Next1["Next"]
IncMin --> Next1
Next1 --> Three["ageMs <= 3s?"]
Three --> |Yes| IncThree["Increment refreshesLast3Seconds<br/>Capture lastRefreshIpHash if unset"]
Three --> |No| Next2["Next"]
IncThree --> Next2
Next2 --> Loop
Loop --> Done["End iteration"]
Done --> Race{"refreshesLast3Seconds >= 1<br/>and lastRefreshIpHash exists<br/>and lastRefreshIpHash != currentIpHash?"}
Race --> |Yes| HardBurn["Return {action:'hard_burn', reason:'concurrent_refresh_different_ip'}"]
Race --> |No| Risk["Compute additionalRisk:<br/>+30 if refreshesLastMinute >= 5<br/>+20 if activeSessionsCount > 10"]
Risk --> Ok["Return {action:'ok', additionalRisk}"]
```

**Diagram sources**
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L130)

**Section sources**
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L130)

### Integration with Risk Scoring
The session continuity result is combined with other risk signals:
- Decayed risk: Reduces historical risk based on elapsed time since last seen.
- Refresh risk: Compares device, user agent, and IP hashes between stored and current contexts.
- Additional risk: From session continuity checks.

Decision thresholds:
- Hard burn: Immediate global session burn when accumulated risk meets or exceeds a high threshold.
- Soft lock: Reject refresh and require re-authentication without burning other sessions when a moderate threshold is met.

```mermaid
flowchart TD
A["Decayed Risk"] --> Sum["cumulativeRisk = decayed + refreshRisk + additionalRisk"]
B["Refresh Risk"] --> Sum
C["Additional Risk (Continuity)"] --> Sum
Sum --> Hard{"cumulativeRisk >= hard_threshold?"}
Hard --> |Yes| Burn["executeFullSessionBurn(userId, reason)"]
Hard --> |No| Soft{"cumulativeRisk >= soft_threshold?"}
Soft --> |Yes| Lock["Reject refresh with re-auth required"]
Soft --> |No| Rotate["Issue new token pair"]
```

**Diagram sources**
- [auth.js](file://backend/src/routes/auth.js#L216-L230)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L36-L49)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L11-L30)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L55-L65)

**Section sources**
- [auth.js](file://backend/src/routes/auth.js#L216-L230)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L36-L49)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L11-L30)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L55-L65)

### Practical Examples and Risk Assessment Scenarios
- Concurrent refresh race condition:
  - Scenario: Two simultaneous refresh requests from different IPs within 3 seconds for the same user.
  - Outcome: Hard burn immediately to contain potential session takeover.
- Token refresh storm:
  - Scenario: A user rapidly rotates refresh tokens more than 5 times within a minute.
  - Outcome: Elevated additional risk contributes to higher cumulative risk, potentially triggering soft lock or hard burn depending on thresholds.
- Active session cap violation:
  - Scenario: A user maintains more than 10 active refresh tokens concurrently.
  - Outcome: Additional risk applied; combined with other factors determines enforcement action.
- Normal behavior:
  - Scenario: Standard refresh activity with typical intervals and reasonable active session counts.
  - Outcome: No additional risk; refresh proceeds normally.

[No sources needed since this section provides general guidance]

## Dependency Analysis
- Routes depend on middleware for device context hashing and on the risk engine for session continuity checks.
- Risk engine depends on Firestore for querying refresh tokens and on logging for diagnostics.
- Device context middleware depends on cryptographic hashing to anonymize identifiers.

```mermaid
graph LR
Auth["Routes: auth.js"] --> DC["Middleware: deviceContext.js"]
Auth --> RE["Service: RiskEngine.js"]
RE --> DB["Firestore: firebase.js"]
DC --> Auth
```

**Diagram sources**
- [auth.js](file://backend/src/routes/auth.js#L166-L280)
- [deviceContext.js](file://backend/src/middleware/deviceContext.js#L1-L24)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L130)
- [firebase.js](file://backend/src/config/firebase.js#L41-L46)

**Section sources**
- [auth.js](file://backend/src/routes/auth.js#L166-L280)
- [deviceContext.js](file://backend/src/middleware/deviceContext.js#L1-L24)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L71-L130)
- [firebase.js](file://backend/src/config/firebase.js#L41-L46)

## Performance Considerations
- Query scope: Limits recent token retrieval to 15 entries per user, reducing collection scan overhead.
- In-memory hashing: Device and IP identifiers are hashed in middleware to avoid storing sensitive data.
- Batch updates: Global session burns use Firestore batch operations to minimize write amplification.
- Logging: Structured logs include user identifiers and reasons to support incident response without exposing sensitive data.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and resolutions:
- Missing device ID on refresh:
  - Symptom: 400 error indicating device ID requirement.
  - Cause: Missing x-device-id header.
  - Resolution: Ensure clients include the device identifier header.
- Session continuity hard burn:
  - Symptom: 401 Session compromised.
  - Cause: Concurrent refresh race detected across different IPs within 3 seconds.
  - Resolution: Advise user to authenticate again; investigate potential device compromise.
- Soft lock requiring re-authentication:
  - Symptom: 401 with instruction to re-authenticate.
  - Cause: Accumulated risk meets soft lock threshold after combining decayed risk, refresh risk, and additional risk.
  - Resolution: Prompt user to log in again; review behavior patterns.
- Database query failures:
  - Symptom: Error logs during session continuity evaluation.
  - Cause: Firestore read failure or timeout.
  - Resolution: Retry logic is implicit in the method returning safe defaults; verify Firestore connectivity and permissions.

**Section sources**
- [deviceContext.js](file://backend/src/middleware/deviceContext.js#L12-L14)
- [auth.js](file://backend/src/routes/auth.js#L211-L214)
- [auth.js](file://backend/src/routes/auth.js#L226-L230)
- [RiskEngine.js](file://backend/src/services/RiskEngine.js#L126-L129)

## Conclusion
The Session Continuity Intelligence system provides robust detection of concurrent refresh races, velocity abuse, and excessive active sessions. By integrating with broader risk scoring and enforcing immediate containment when necessary, it strengthens protection against session hijacking and token misuse while maintaining operational safety and user experience.