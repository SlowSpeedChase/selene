#!/usr/bin/env python3
"""
Mobile PWA Demo for Selene Second Brain Processing System
Demonstrates mobile-specific features and PWA capabilities
"""

import os
import sys
import time
import asyncio
import subprocess
from pathlib import Path
from rich.console import Console
from rich.panel import Panel
from rich.layout import Layout
from rich.text import Text
from rich.live import Live
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TimeElapsedColumn

console = Console()

def print_header():
    """Print the demo header."""
    console.print(Panel.fit(
        """
[bold green]🧠 Selene Mobile PWA Demo[/bold green]
[cyan]Progressive Web App for Local AI Processing[/cyan]

[yellow]Features Demonstrated:[/yellow]
• 📱 Progressive Web App (PWA) installation
• 🔄 Service Worker with offline caching
• 🎤 Voice input for note capture
• 📱 Mobile-optimized responsive design
• 🌐 Offline processing queue
• 📲 Push notifications
• 👆 Touch gestures and mobile navigation

[blue]Privacy-First Architecture:[/blue]
• 🔒 100% Local processing (no data leaves your device)
• 🚫 No usage fees or subscriptions
• 📡 Works offline after initial load
• 💾 Local vector database and embeddings
        """,
        title="SMS-20 Mobile Interface Demo",
        border_style="green"
    ))

def check_requirements():
    """Check if all requirements are met."""
    console.print("\n[yellow]Checking requirements...[/yellow]")
    
    requirements = [
        ("Python 3.9+", sys.version_info >= (3, 9)),
        ("Selene package", Path("selene").exists()),
        ("Web static files", Path("selene/web/static").exists()),
        ("PWA manifest", Path("selene/web/static/manifest.json").exists()),
        ("Service Worker", Path("selene/web/static/sw.js").exists()),
        ("Mobile CSS", Path("selene/web/static/css/mobile.css").exists()),
        ("Mobile JS", Path("selene/web/static/js/mobile.js").exists()),
        ("PWA Icons", Path("selene/web/static/icons").exists()),
    ]
    
    table = Table(title="Requirements Check", show_header=True, header_style="bold magenta")
    table.add_column("Component", style="cyan")
    table.add_column("Status", justify="center")
    
    all_good = True
    for name, check in requirements:
        if check:
            table.add_row(name, "[green]✅ OK[/green]")
        else:
            table.add_row(name, "[red]❌ MISSING[/red]")
            all_good = False
    
    console.print(table)
    
    if not all_good:
        console.print("\n[red]❌ Some requirements are missing. Please run the setup first.[/red]")
        return False
    
    console.print("\n[green]✅ All requirements met![/green]")
    return True

def start_web_server():
    """Start the Selene web server."""
    console.print("\n[yellow]Starting Selene web server...[/yellow]")
    
    try:
        # Start the web server in background
        process = subprocess.Popen(
            [sys.executable, "-m", "selene.main", "web", "--port", "8080"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        # Wait a bit for server to start
        time.sleep(3)
        
        # Check if server is running
        if process.poll() is None:
            console.print("[green]✅ Web server started at http://127.0.0.1:8080[/green]")
            return process
        else:
            console.print("[red]❌ Failed to start web server[/red]")
            return None
            
    except Exception as e:
        console.print(f"[red]❌ Error starting web server: {e}[/red]")
        return None

def demonstrate_pwa_features():
    """Demonstrate PWA features."""
    console.print("\n[bold cyan]📱 Progressive Web App Features[/bold cyan]")
    
    features = [
        ("📱 App Installation", "Install Selene as a native mobile app"),
        ("🔄 Service Worker", "Offline caching and background sync"),
        ("📲 Push Notifications", "Processing complete notifications"),
        ("🎨 App Icons", "Custom icons for all device sizes"),
        ("🌐 Offline Support", "Continue working without internet"),
        ("📊 App Manifest", "PWA metadata and configuration"),
    ]
    
    table = Table(title="PWA Features", show_header=True, header_style="bold magenta")
    table.add_column("Feature", style="cyan")
    table.add_column("Description", style="white")
    
    for feature, description in features:
        table.add_row(feature, description)
    
    console.print(table)
    
    console.print("\n[yellow]Mobile Installation Instructions:[/yellow]")
    console.print("• [cyan]iOS Safari[/cyan]: Tap Share → Add to Home Screen")
    console.print("• [cyan]Android Chrome[/cyan]: Tap menu → Add to Home Screen")
    console.print("• [cyan]Desktop Chrome[/cyan]: Click install icon in address bar")

def demonstrate_mobile_ui():
    """Demonstrate mobile UI features."""
    console.print("\n[bold cyan]📱 Mobile UI Features[/bold cyan]")
    
    ui_features = [
        ("🎤 Voice Input", "Speech-to-text for quick note capture"),
        ("👆 Touch Gestures", "Swipe navigation between tabs"),
        ("📱 Responsive Design", "Optimized for all screen sizes"),
        ("🍔 Mobile Menu", "Collapsible navigation on small screens"),
        ("🔄 Pull to Refresh", "Refresh content with pull gesture"),
        ("📝 Touch-Friendly Forms", "Large buttons and inputs"),
        ("🌙 Dark Mode Support", "System preference detection"),
        ("⚡ Fast Loading", "Optimized for mobile networks"),
    ]
    
    table = Table(title="Mobile UI Features", show_header=True, header_style="bold magenta")
    table.add_column("Feature", style="cyan")
    table.add_column("Description", style="white")
    
    for feature, description in ui_features:
        table.add_row(feature, description)
    
    console.print(table)

def demonstrate_offline_features():
    """Demonstrate offline functionality."""
    console.print("\n[bold cyan]🔄 Offline Features[/bold cyan]")
    
    offline_features = [
        ("📦 Static Caching", "Cache app shell and resources"),
        ("🔄 Dynamic Caching", "Cache API responses and data"),
        ("📤 Background Sync", "Process queued actions when online"),
        ("💾 Local Storage", "Store user data locally"),
        ("🔄 Sync Detection", "Detect online/offline state"),
        ("📋 Offline Queue", "Queue processing requests"),
        ("🔄 Auto Retry", "Retry failed requests when back online"),
        ("📊 Cache Management", "Smart cache invalidation"),
    ]
    
    table = Table(title="Offline Features", show_header=True, header_style="bold magenta")
    table.add_column("Feature", style="cyan")
    table.add_column("Description", style="white")
    
    for feature, description in offline_features:
        table.add_row(feature, description)
    
    console.print(table)

def demonstrate_voice_input():
    """Demonstrate voice input capabilities."""
    console.print("\n[bold cyan]🎤 Voice Input Features[/bold cyan]")
    
    voice_features = [
        ("🎙️ Speech Recognition", "Web Speech API integration"),
        ("🔊 Audio Feedback", "Visual feedback during recording"),
        ("📝 Text Conversion", "Convert speech to text for processing"),
        ("🛑 Start/Stop Control", "Easy recording controls"),
        ("🌍 Multi-Language", "Support for multiple languages"),
        ("🔇 Privacy First", "All processing happens locally"),
        ("📱 Mobile Optimized", "Touch-friendly voice controls"),
        ("⚡ Real-time", "Instant speech-to-text conversion"),
    ]
    
    table = Table(title="Voice Input Features", show_header=True, header_style="bold magenta")
    table.add_column("Feature", style="cyan")
    table.add_column("Description", style="white")
    
    for feature, description in voice_features:
        table.add_row(feature, description)
    
    console.print(table)
    
    console.print("\n[yellow]Voice Input Usage:[/yellow]")
    console.print("• Navigate to 'Process Content' tab")
    console.print("• Click the microphone button next to the text area")
    console.print("• Speak your note content")
    console.print("• Text will appear automatically")
    console.print("• Process with your preferred AI model")

def show_mobile_demo_summary():
    """Show the mobile demo summary."""
    console.print("\n[bold green]📱 Mobile Demo Summary[/bold green]")
    
    console.print(Panel.fit(
        """
[bold cyan]🎉 SMS-20 Mobile Interface Complete![/bold cyan]

[yellow]What You've Seen:[/yellow]
• 📱 Progressive Web App with full mobile support
• 🔄 Service Worker with offline caching
• 🎤 Voice input for hands-free note capture
• 👆 Touch gestures and mobile navigation
• 📱 Responsive design for all screen sizes
• 🌐 Offline processing queue
• 📲 Push notifications (when supported)

[yellow]Key Benefits:[/yellow]
• 🔒 100% Local processing (privacy-first)
• 📱 Native app experience on mobile
• 🌐 Works offline after initial load
• 🎤 Voice input for quick capture
• ⚡ Fast, responsive mobile interface
• 📊 Same powerful AI features as desktop

[yellow]Next Steps:[/yellow]
• Install the PWA on your mobile device
• Test voice input functionality
• Try offline processing capabilities
• Explore touch gestures and navigation

[green]Ready for production use! 🚀[/green]
        """,
        title="Mobile PWA Demo Complete",
        border_style="green"
    ))

def main():
    """Main demo function."""
    try:
        print_header()
        
        # Check requirements
        if not check_requirements():
            return
        
        # Start web server
        server_process = start_web_server()
        if not server_process:
            return
        
        try:
            # Demonstrate features
            demonstrate_pwa_features()
            
            console.print("\n[yellow]Press Enter to continue...[/yellow]")
            input()
            
            demonstrate_mobile_ui()
            
            console.print("\n[yellow]Press Enter to continue...[/yellow]")
            input()
            
            demonstrate_offline_features()
            
            console.print("\n[yellow]Press Enter to continue...[/yellow]")
            input()
            
            demonstrate_voice_input()
            
            console.print("\n[yellow]Press Enter to continue...[/yellow]")
            input()
            
            show_mobile_demo_summary()
            
            console.print("\n[bold green]🌐 Web server running at: http://127.0.0.1:8080[/bold green]")
            console.print("[cyan]Visit on your mobile device to test PWA features![/cyan]")
            console.print("\n[yellow]Press Enter to stop the server...[/yellow]")
            input()
            
        finally:
            # Clean up
            if server_process and server_process.poll() is None:
                server_process.terminate()
                server_process.wait()
                console.print("\n[green]✅ Web server stopped[/green]")
    
    except KeyboardInterrupt:
        console.print("\n[yellow]Demo interrupted by user[/yellow]")
    except Exception as e:
        console.print(f"\n[red]❌ Demo error: {e}[/red]")

if __name__ == "__main__":
    main()