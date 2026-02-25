# Debug Endpoint

<cite>
**Referenced Files in This Document**
- [auth.js](file://backend/src/routes/auth.js)
- [app.js](file://backend/src/app.js)
- [firebase.js](file://backend/src/config/firebase.js)
- [env.js](file://backend/src/config/env.js)
- [.env.example](file://backend/.env.example)
- [.env](file://backend/.env)
- [security.js](file://backend/src/middleware/security.js)
- [progressiveLimiter.js](file://backend/src/middleware/progressiveLimiter.js)
- [logger.js](file://backend/src/utils/logger.js)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Endpoint Specification](#endpoint-specification)
3. [Response Schema](#response-schema)
4. [Purpose and Use Cases](#purpose-and-use-cases)
5. [Development Workflow Integration](#development-workflow-integration)
6. [Security Considerations](#security-considerations)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Related Configuration](#related-configuration)

## Introduction

The `/api/auth/debug` endpoint is a development-only utility designed to help developers verify and troubleshoot Firebase configuration during the development phase. This endpoint provides immediate feedback on the current environment configuration, particularly focusing on Firebase project setup and authentication flow validation.

The endpoint serves as a diagnostic tool that allows developers to quickly confirm whether their Firebase service account credentials are properly configured and accessible to the backend application. It's specifically intended for development environments and should never be exposed in production systems.

## Endpoint Specification

### HTTP Method and Route
- **Method:** GET
- **Route:** `/api/auth/debug`
- **Authentication:** Not required (public endpoint)

### Request Details
- **Content-Type:** Not applicable (GET request)
- **Authentication:** None required
- **Rate Limiting:** Subject to progressive rate limiting policy

### Response Format
The endpoint returns a standardized JSON response containing configuration verification data and timestamp information.

**Section sources**
- [auth.js](file://backend/src/routes/auth.js#L282-L298)

## Response Schema

The debug endpoint returns a structured JSON object with the following schema:

```json
{
  "success": true,
  "data": {
    "projectId": "string | null",
    "nodeEnv": "string",
    "hasPrivateKey": "boolean",
    "clientEmail": "string | null",
    "timestamp": "string"
  }
}
```

### Response Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `success` | boolean | Indicates successful response | `true` |
| `data.projectId` | string/null | Firebase project identifier from environment | `"testpro-73a93"` |
| `data.nodeEnv` | string | Current Node.js environment setting | `"development"` |
| `data.hasPrivateKey` | boolean | Presence indicator for private key | `true` |
| `data.clientEmail` | string/null | Firebase service account email | `"firebase-adminsdk-fbsvc@testpro-73a93.iam.gserviceaccount.com"` |
| `data.timestamp` | string | ISO 8601 timestamp of response | `"2024-01-15T10:30:45.123Z"` |

**Section sources**
- [auth.js](file://backend/src/routes/auth.js#L288-L297)

## Purpose and Use Cases

### Primary Objectives

1. **Firebase Project Verification**
   - Confirms that the Firebase project ID is correctly loaded from environment variables
   - Validates that the service account credentials are accessible to the application

2. **Environment Configuration Validation**
   - Tests the NODE_ENV variable setup for proper development/production distinction
   - Verifies that sensitive environment variables are properly loaded

3. **Authentication Flow Debugging**
   - Provides quick confirmation that Firebase Admin SDK initialization succeeded
   - Helps identify configuration issues before attempting actual authentication operations

### Common Development Scenarios

#### Initial Setup Validation
- After configuring `.env` file, immediately verify Firebase credentials
- Confirm that private key and client email are properly formatted
- Test environment variable loading across different development environments

#### Configuration Change Testing
- After updating Firebase service account credentials
- Verify that environment variable changes are reflected in the application
- Test private key formatting and newline character handling

#### Troubleshooting Authentication Issues
- Isolate configuration problems from actual authentication failures
- Determine if Firebase Admin SDK can establish connection to Google Cloud
- Verify service account permissions and project membership

**Section sources**
- [auth.js](file://backend/src/routes/auth.js#L283-L285)

## Development Workflow Integration

### Integration Points

The debug endpoint integrates seamlessly with the existing application architecture:

```mermaid
sequenceDiagram
participant Dev as "Developer"
participant Client as "HTTP Client"
participant App as "Express App"
participant Router as "Auth Router"
participant Env as "Environment Config"
Dev->>Client : GET /api/auth/debug
Client->>App : HTTP Request
App->>Router : Route to /api/auth/debug
Router->>Env : Read environment variables
Env-->>Router : Configuration values
Router-->>Client : JSON response with config details
Client-->>Dev : Debug information
```

**Diagram sources**
- [auth.js](file://backend/src/routes/auth.js#L287-L297)
- [app.js](file://backend/src/app.js#L39)

### Rate Limiting Context

The endpoint is subject to the progressive rate limiting system, which provides protection against abuse while maintaining developer convenience:

- **Policy Context:** `auth` policy (same as authentication routes)
- **Default Limits:** 5 requests per 10 minutes for IP-based identification
- **Protection Level:** Moderate protection suitable for development environments

**Section sources**
- [progressiveLimiter.js](file://backend/src/middleware/progressiveLimiter.js#L5-L15)
- [app.js](file://backend/src/app.js#L39)

## Security Considerations

### Development-Only Design

The debug endpoint is explicitly designed for development environments and should never be exposed in production:

1. **No Authentication Required**
   - Public endpoint accessible without credentials
   - Intentionally designed for easy developer access

2. **Limited Sensitive Information**
   - Returns only environment variable values
   - Does not expose actual private key content (only presence indicator)
   - Client email is returned as-is, but this is typically public information

3. **Environment-Based Protection**
   - Automatically disabled in production environments through middleware
   - Development-focused logging and error handling

### Production Safety Measures

While the endpoint itself is safe, several application-level protections prevent exposure:

- **CORS Configuration:** Development-friendly CORS settings
- **Security Headers:** Comprehensive header protection for production
- **Rate Limiting:** Prevents abuse while allowing normal development usage
- **Logging:** Minimal logging focused on development diagnostics

**Section sources**
- [security.js](file://backend/src/middleware/security.js#L25-L46)

## Troubleshooting Guide

### Common Issues and Solutions

#### Empty or Null Values
**Symptoms:** Response shows null values for configuration fields
**Causes:**
- Environment variables not properly set
- `.env` file not loaded correctly
- Wrong environment file (.env vs .env.production)

**Solutions:**
1. Verify `.env` file contains all required Firebase variables
2. Check that the application is loading the correct environment file
3. Restart the development server to reload environment variables

#### Private Key Issues
**Symptoms:** `hasPrivateKey` returns `false` despite having a key
**Causes:**
- Private key not properly quoted in `.env` file
- Missing newline characters (`\n`) in the key
- Copy-paste formatting issues

**Solutions:**
1. Ensure private key is enclosed in quotes in `.env`
2. Preserve literal `\n` characters for newlines
3. Use the format shown in `.env.example`

#### Environment Variable Loading Problems
**Symptoms:** `nodeEnv` shows unexpected value or configuration errors
**Causes:**
- Incorrect `.env` file placement
- Environment variable name typos
- Application not restarting after `.env` changes

**Solutions:**
1. Verify `.env` file is in the correct location
2. Check for typos in environment variable names
3. Restart the development server completely

### Diagnostic Workflow

1. **Initial Check:** Call `/api/auth/debug` to verify basic configuration
2. **Environment Validation:** Confirm `nodeEnv` equals `"development"`
3. **Credential Verification:** Ensure `hasPrivateKey` is `true`
4. **Project ID Validation:** Verify `projectId` matches expected Firebase project
5. **Client Email Check:** Confirm `clientEmail` format is correct

**Section sources**
- [auth.js](file://backend/src/routes/auth.js#L287-L297)
- [.env.example](file://backend/.env.example#L9-L13)

## Related Configuration

### Environment Variables

The debug endpoint relies on several key environment variables:

| Variable | Purpose | Required | Example |
|----------|---------|----------|---------|
| `FIREBASE_PROJECT_ID` | Firebase project identifier | Yes | `testpro-73a93` |
| `FIREBASE_PRIVATE_KEY` | Service account private key | Yes | `"-----BEGIN PRIVATE KEY-----\\n..."` |
| `FIREBASE_CLIENT_EMAIL` | Service account email | Yes | `firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com` |
| `NODE_ENV` | Environment type | Yes | `development` |
| `JWT_ACCESS_SECRET` | Access token signing key | Yes | Random secure string |

### Configuration Files

The application loads configuration from multiple sources:

1. **`.env.example`** - Template with all available configuration options
2. **`.env`** - Actual environment configuration for current deployment
3. **`.env.production`** - Production-specific overrides

**Section sources**
- [.env.example](file://backend/.env.example#L1-L25)
- [.env](file://backend/.env#L1-L22)
- [env.js](file://backend/src/config/env.js#L6-L22)

### Firebase Configuration

The Firebase Admin SDK initialization validates configuration:

```mermaid
flowchart TD
Start([Application Startup]) --> LoadEnv["Load Environment Variables"]
LoadEnv --> ValidateVars["Validate Required Variables"]
ValidateVars --> VarsMissing{"Variables Present?"}
VarsMissing --> |No| LogError["Log Missing Variables"]
VarsMissing --> |Yes| InitFirebase["Initialize Firebase Admin"]
InitFirebase --> InitSuccess{"Initialization<br/>Successful?"}
InitSuccess --> |No| FatalError["Process Exit with Error"]
InitSuccess --> |Yes| Ready["Ready for Debug Requests"]
LogError --> FatalError
```

**Diagram sources**
- [firebase.js](file://backend/src/config/firebase.js#L7-L17)
- [firebase.js](file://backend/src/config/firebase.js#L27-L39)

**Section sources**
- [firebase.js](file://backend/src/config/firebase.js#L1-L46)