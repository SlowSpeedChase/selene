#!/usr/bin/env node

/**
 * Things HTTP Wrapper (AppleScript)
 *
 * Provides HTTP endpoints for n8n to interact with Things via AppleScript.
 * Simpler and more reliable than MCP stdio communication.
 *
 * Usage:
 *   node scripts/things-mcp-wrapper.js
 *
 * Endpoints:
 *   POST /create-task - Create a new task in Things
 *   GET /health - Health check
 */

const express = require('express');
const { execSync } = require('child_process');
const app = express();
const PORT = process.env.MCP_WRAPPER_PORT || 3456;

app.use(express.json());

/**
 * Create task in Things via URL scheme
 * More reliable than AppleScript for complex parameters
 */
function createThingsTask(params) {
  const { title, notes, tags, when, checklist_items } = params;

  // Build Things URL
  let url = 'things:///add?';
  const urlParams = new URLSearchParams();

  urlParams.append('title', title);

  if (notes) {
    urlParams.append('notes', notes);
  }

  if (tags && tags.length > 0) {
    urlParams.append('tags', tags.join(','));
  }

  if (when) {
    urlParams.append('when', when);
  }

  if (checklist_items && checklist_items.length > 0) {
    urlParams.append('checklist-items', checklist_items.join('\n'));
  }

  url += urlParams.toString();

  // Use 'open' command to trigger Things URL scheme
  try {
    execSync(`open "${url}"`, {
      encoding: 'utf8',
      timeout: 5000
    });

    // Note: Things URL scheme doesn't return task ID
    // We'll return success without ID
    return {
      success: true,
      task_id: null,
      message: 'Task created successfully (ID not available via URL scheme)'
    };
  } catch (error) {
    throw new Error(`Things URL scheme failed: ${error.message}`);
  }
}

/**
 * POST /create-task
 * Create a new task in Things
 *
 * Body:
 * {
 *   "title": "Task title",
 *   "notes": "Optional notes",
 *   "tags": ["tag1", "tag2"],
 *   "when": "today" | "tomorrow" | "anytime" | "YYYY-MM-DD",
 *   "checklist_items": ["Step 1", "Step 2"],
 *   "passthrough": { ... }  // Optional: any data to return in response
 * }
 */
app.post('/create-task', async (req, res) => {
  try {
    const { title, notes, tags, when, checklist_items, passthrough } = req.body;

    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }

    console.log(`Creating task: "${title}"`);
    console.log('FULL REQUEST BODY:', JSON.stringify(req.body, null, 2).substring(0, 500));
    console.log('Passthrough data received:', passthrough ? 'YES' : 'NO');
    if (passthrough) {
      console.log('Passthrough keys:', Object.keys(passthrough));
      console.log('Passthrough data:', JSON.stringify(passthrough, null, 2).substring(0, 300));
    }

    const result = createThingsTask({
      title,
      notes,
      tags,
      when,
      checklist_items
    });

    console.log(`✅ Task created: ${result.task_id}`);

    // Include passthrough data in response if provided
    const response = {
      ...result,
      ...(passthrough && { passthrough })
    };

    res.json(response);
  } catch (error) {
    console.error('❌ Error creating task:', error.message);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * GET /health
 * Health check endpoint
 */
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

/**
 * Start server
 */
app.listen(PORT, () => {
  console.log(`✅ Things HTTP Wrapper (AppleScript) running on port ${PORT}`);
  console.log(`   POST http://localhost:${PORT}/create-task`);
  console.log(`   GET  http://localhost:${PORT}/health`);
});

// Handle shutdown gracefully
process.on('SIGINT', () => {
  console.log('\n👋 Shutting down gracefully...');
  process.exit(0);
});
