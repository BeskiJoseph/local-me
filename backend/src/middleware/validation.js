/**
 * Request Validation Middleware - Centralized input validation
 * 
 * All API input is validated here before reaching controllers.
 * Provides consistent error responses across all endpoints.
 */

import Joi from 'joi';
import logger from '../utils/logger.js';

// ============================================================
// Validation Schemas
// ============================================================

export const schemas = {
  // Post creation/update
  post: Joi.object({
    title: Joi.string().max(2000).required().messages({
      'string.empty': 'Title is required',
      'string.max': 'Title must not exceed 2000 characters'
    }),
    body: Joi.string().max(5000).required().messages({
      'string.empty': 'Post content is required',
      'string.max': 'Post content must not exceed 5000 characters'
    }),
    city: Joi.string().max(100).allow(null, ''),
    country: Joi.string().max(100).allow(null, ''),
    latitude: Joi.number().min(-90).max(90).allow(null),
    longitude: Joi.number().min(-180).max(180).allow(null),
    geoHash: Joi.string().min(1).max(12).allow(null, ''),
    mediaType: Joi.string().valid('none', 'image', 'video', 'audio').default('none'),
    mediaUrl: Joi.string().uri().allow(null, ''),
    visibility: Joi.string().valid('public', 'private', 'friends').default('public'),
    status: Joi.string().valid('active', 'archived', 'deleted').default('active'),
    category: Joi.string().max(50).allow(null, ''),
    searchTokens: Joi.array().items(Joi.string()).allow(null)
  }),

  // Feed query parameters
  feedQuery: Joi.object({
    lat: Joi.number().min(-90).max(90),
    lng: Joi.number().min(-180).max(180),
    limit: Joi.number().integer().min(1).max(50).default(20),
    afterId: Joi.string().allow(null, ''),
    watchedIds: Joi.string().allow(null, ''),
    mediaType: Joi.string().valid('none', 'image', 'video', 'audio').allow(null, ''),
    sid: Joi.string().allow(null, ''), // Session ID
    cursor: Joi.string().allow(null, ''), // Composite cursor
    feedType: Joi.string().valid('local', 'global', 'hybrid', 'filtered').allow(null, ''),
    authorId: Joi.string().allow(null, ''),
    category: Joi.string().allow(null, ''),
    city: Joi.string().allow(null, ''),
    country: Joi.string().allow(null, '')
  }),

  // Pagination
  pagination: Joi.object({
    limit: Joi.number().integer().min(1).max(50).default(20),
    offset: Joi.number().integer().min(0).default(0),
    afterId: Joi.string().allow(null, '')
  }),

  // Geolocation
  location: Joi.object({
    lat: Joi.number().min(-90).max(90).required(),
    lng: Joi.number().min(-180).max(180).required()
  }),

  // Post ID
  postId: Joi.object({
    id: Joi.string().required().messages({
      'string.empty': 'Post ID is required'
    })
  })
};

// ============================================================
// Middleware Factories
// ============================================================

/**
 * Validate request body
 */
export function validateBody(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.body, {
      abortEarly: false,
      stripUnknown: true
    });

    if (error) {
      const messages = error.details.map(d => d.message).join('; ');
      logger.warn({ messages, path: req.path }, '[Validation] Body validation failed');
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.details.map(d => ({
          field: d.path.join('.'),
          message: d.message
        }))
      });
    }

    req.body = value;
    next();
  };
}

/**
 * Validate request query
 */
export function validateQuery(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.query, {
      abortEarly: false,
      stripUnknown: true
    });

    if (error) {
      const messages = error.details.map(d => d.message).join('; ');
      logger.warn({ messages, path: req.path }, '[Validation] Query validation failed');
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.details.map(d => ({
          field: d.path.join('.'),
          message: d.message
        }))
      });
    }

    req.query = value;
    next();
  };
}

/**
 * Validate request params
 */
export function validateParams(schema) {
  return (req, res, next) => {
    const { error, value } = schema.validate(req.params, {
      abortEarly: false,
      stripUnknown: true
    });

    if (error) {
      const messages = error.details.map(d => d.message).join('; ');
      logger.warn({ messages, path: req.path }, '[Validation] Params validation failed');
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.details.map(d => ({
          field: d.path.join('.'),
          message: d.message
        }))
      });
    }

    req.params = value;
    next();
  };
}

/**
 * Global validation error handler
 * Should be used as the last middleware in app.js
 */
export function validationErrorHandler(err, req, res, next) {
  if (err instanceof Joi.ValidationError) {
    logger.warn({ error: err.message }, '[Validation] Global validation error');
    return res.status(400).json({
      success: false,
      message: 'Validation error',
      errors: err.details.map(d => ({
        field: d.path.join('.'),
        message: d.message
      }))
    });
  }
  next(err);
}
