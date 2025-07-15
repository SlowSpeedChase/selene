#!/usr/bin/env python3
"""
Generate PWA icons for Selene
Creates various sized icons from a base SVG or creates simple colored squares
"""

import os
from PIL import Image, ImageDraw, ImageFont
import json

# Icon sizes for PWA
ICON_SIZES = [
    16, 32, 72, 96, 128, 144, 152, 192, 384, 512
]

# Colors for the icon
BACKGROUND_COLOR = '#4CAF50'
TEXT_COLOR = '#FFFFFF'
SECONDARY_COLOR = '#2E7D32'

def create_icon(size, save_path):
    """Create a simple brain icon with 'S' for Selene"""
    # Create image
    img = Image.new('RGB', (size, size), BACKGROUND_COLOR)
    draw = ImageDraw.Draw(img)
    
    # Draw brain shape (simplified as circle with some details)
    margin = size // 8
    circle_size = size - 2 * margin
    
    # Main brain circle
    draw.ellipse([margin, margin, margin + circle_size, margin + circle_size], 
                fill=SECONDARY_COLOR, outline=TEXT_COLOR, width=2)
    
    # Brain details (simplified)
    center_x, center_y = size // 2, size // 2
    
    # Left brain hemisphere
    draw.arc([margin + 5, margin + 5, margin + circle_size//2, margin + circle_size//2], 
             0, 180, fill=TEXT_COLOR, width=1)
    
    # Right brain hemisphere  
    draw.arc([center_x, margin + 5, margin + circle_size - 5, margin + circle_size//2], 
             0, 180, fill=TEXT_COLOR, width=1)
    
    # Add 'S' in center
    try:
        font_size = max(size // 4, 12)
        font = ImageFont.truetype('/System/Library/Fonts/Arial.ttf', font_size)
    except:
        font = ImageFont.load_default()
    
    # Get text bbox
    bbox = draw.textbbox((0, 0), 'S', font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    # Center the text
    text_x = (size - text_width) // 2
    text_y = (size - text_height) // 2
    
    draw.text((text_x, text_y), 'S', fill=TEXT_COLOR, font=font)
    
    # Save
    img.save(save_path, 'PNG')
    print(f"Created icon: {save_path}")

def create_all_icons():
    """Create all required PWA icons"""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    for size in ICON_SIZES:
        filename = f'icon-{size}x{size}.png'
        filepath = os.path.join(base_dir, filename)
        create_icon(size, filepath)
    
    # Create apple-touch-icon sizes
    apple_sizes = [152, 180]
    for size in apple_sizes:
        filename = f'icon-{size}x{size}.png'
        filepath = os.path.join(base_dir, filename)
        if not os.path.exists(filepath):
            create_icon(size, filepath)
    
    print("✅ All icons created successfully!")
    print(f"Created {len(ICON_SIZES) + len([s for s in apple_sizes if s not in ICON_SIZES])} icons")

def create_favicon():
    """Create favicon.ico"""
    base_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Create multiple sizes for favicon
    favicon_sizes = [16, 32, 48]
    images = []
    
    for size in favicon_sizes:
        img = Image.new('RGB', (size, size), BACKGROUND_COLOR)
        draw = ImageDraw.Draw(img)
        
        # Simple 'S' favicon
        try:
            font_size = max(size // 2, 8)
            font = ImageFont.truetype('/System/Library/Fonts/Arial.ttf', font_size)
        except:
            font = ImageFont.load_default()
        
        bbox = draw.textbbox((0, 0), 'S', font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
        
        text_x = (size - text_width) // 2
        text_y = (size - text_height) // 2
        
        draw.text((text_x, text_y), 'S', fill=TEXT_COLOR, font=font)
        images.append(img)
    
    # Save as favicon.ico
    favicon_path = os.path.join(base_dir, 'favicon.ico')
    images[0].save(favicon_path, format='ICO', sizes=[(img.width, img.height) for img in images])
    print(f"Created favicon: {favicon_path}")

if __name__ == '__main__':
    try:
        create_all_icons()
        create_favicon()
        print("🎉 PWA icons generation complete!")
    except Exception as e:
        print(f"❌ Error generating icons: {e}")
        print("Make sure you have Pillow installed: pip install Pillow")