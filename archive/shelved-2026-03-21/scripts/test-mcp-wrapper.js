#!/usr/bin/env node

/**
 * Test script for Things MCP HTTP Wrapper
 *
 * Tests the wrapper by creating a test task and verifying it works.
 */

const http = require('http');

const WRAPPER_URL = 'http://localhost:3456';

function makeRequest(path, method, body) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost',
      port: 3456,
      path,
      method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          resolve(data);
        }
      });
    });

    req.on('error', reject);

    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runTests() {
  console.log('🧪 Testing Things MCP HTTP Wrapper\n');

  // Test 1: Health check
  console.log('Test 1: Health check...');
  try {
    const health = await makeRequest('/health', 'GET');
    if (health.status === 'ok') {
      console.log('✅ Health check passed\n');
    } else {
      console.log('❌ Health check failed:', health, '\n');
    }
  } catch (error) {
    console.log('❌ Health check error:', error.message);
    console.log('💡 Make sure wrapper is running: npm run mcp-wrapper\n');
    process.exit(1);
  }

  // Test 2: Create test task
  console.log('Test 2: Creating test task...');
  try {
    const result = await makeRequest('/create-task', 'POST', {
      title: 'MCP Wrapper Test Task',
      notes: 'This is a test task created by the MCP wrapper test script.',
      tags: ['test', 'automation'],
      when: 'anytime'
    });

    if (result.success) {
      console.log('✅ Task created successfully');
      console.log('   Task ID:', result.task_id);
      console.log('\n📱 Check Things app - you should see "MCP Wrapper Test Task" in your inbox!');
      console.log('   You can delete it manually after verifying.\n');
    } else {
      console.log('❌ Task creation failed:', result.error, '\n');
    }
  } catch (error) {
    console.log('❌ Task creation error:', error.message, '\n');
  }

  console.log('✨ Tests complete!');
}

runTests();
