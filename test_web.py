#!/usr/bin/env python3
"""
Simple test web server for Selene to debug connectivity issues.
"""

import uvicorn
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from pathlib import Path

app = FastAPI(title="Selene Test Server")

@app.get("/")
def root():
    return {"message": "Selene Test Server", "status": "running"}

@app.get("/dashboard", response_class=HTMLResponse)
def dashboard():
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Selene Dashboard</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .header { background: linear-gradient(135deg, #3b82f6, #10b981); color: white; padding: 20px; border-radius: 8px; }
            .card { background: white; border: 1px solid #e5e7eb; border-radius: 8px; padding: 20px; margin: 20px 0; }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>🧠 Selene Second Brain Processing System</h1>
            <p>Test Dashboard - Web Interface Working!</p>
        </div>
        
        <div class="card">
            <h2>✅ Connection Successful</h2>
            <p>If you can see this page, the Selene web server is working correctly.</p>
            <p><strong>Next step:</strong> The full Selene interface should work at the same URL.</p>
        </div>
        
        <div class="card">
            <h2>🔗 Available Endpoints</h2>
            <ul>
                <li><a href="/">JSON API Status</a></li>
                <li><a href="/dashboard">This Dashboard</a></li>
            </ul>
        </div>
    </body>
    </html>
    """

if __name__ == "__main__":
    print("🌐 Starting Selene Test Web Server")
    print("📍 Dashboard: http://127.0.0.1:8003/dashboard")
    print("📊 API Status: http://127.0.0.1:8003/")
    print("🛑 Press Ctrl+C to stop")
    
    uvicorn.run(app, host="127.0.0.1", port=8003, log_level="info")