# iOS Shortcut: "Capture to Selene"

## Overview

One-tap whiteboard/paper capture. Sends photos to Claude Vision (Haiku 3.5) for interpretation, then POSTs structured markdown to Selene's webhook. Also detects annotated daily planning sheets via the SELENE date label.

## Setup

1. Open Shortcuts app on iPhone/iPad
2. Create new shortcut named "Capture to Selene"
3. Add actions in this order:

## Actions

### 1. Receive Input

- Accept: Images
- If there is no input: Continue (we'll open camera)

### 2. If (no input received)

- Take Photo (from Camera)
- Set variable `photo` to result

### 3. Otherwise

- Set variable `photo` to Shortcut Input

### 4. End If

### 5. Resize Image

- Image: `photo`
- Width: 1024 (saves API cost while maintaining readability)

### 6. Base64 Encode

- Input: resized image

### 7. Get Contents of URL (Claude API)

- URL: `https://api.anthropic.com/v1/messages`
- Method: POST
- Headers:
  - `x-api-key`: YOUR_CLAUDE_API_KEY
  - `anthropic-version`: `2023-06-01`
  - `content-type`: `application/json`
- Request Body (JSON):

```json
{
  "model": "claude-haiku-4-5-20251001",
  "max_tokens": 1024,
  "messages": [{
    "role": "user",
    "content": [
      {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": "image/jpeg",
          "data": "BASE64_ENCODED_IMAGE"
        }
      },
      {
        "type": "text",
        "text": "Interpret this handwritten note or whiteboard. Preserve spatial groupings, arrows, and relationships. Output structured markdown. If you see a label containing 'SELENE' and a date, this is an annotated daily planning sheet — extract only the handwritten annotations, not the printed content. For annotated sheets, output JSON: {\"type\": \"daily_sheet_annotation\", \"date\": \"YYYY-MM-DD\", \"completed_tasks\": [], \"new_notes\": [], \"thread_annotations\": []}. For all other images, output clean markdown."
      }
    ]
  }]
}
```

### 8. Get Dictionary Value

- Key: `content` from API response
- Get first item, then key `text`

### 9. If (result contains "daily_sheet_annotation")

- Set `capture_type` to `daily_sheet_annotation`
- Set `title` to "Daily Sheet Annotations — CURRENT_DATE"

### 10. Otherwise

- Set `capture_type` to `whiteboard`
- Set `title` to "Whiteboard — CURRENT_DATE"

### 11. End If

### 12. Get Contents of URL (POST to Selene)

- URL: `http://YOUR_TAILSCALE_IP:5678/webhook/api/drafts`
- Method: POST
- Headers:
  - `Content-Type`: `application/json`
  - `Authorization`: `Bearer YOUR_SELENE_TOKEN`
- Request Body:

```json
{
  "title": "TITLE_VARIABLE",
  "content": "CLAUDE_RESPONSE_TEXT",
  "capture_type": "CAPTURE_TYPE_VARIABLE"
}
```

### 13. Show Notification

- Title: "Selene"
- Body: "Captured!"

## Offline Fallback

Add an "If (error)" block around step 7 (Claude API call):

- On error: Use "Extract Text from Image" action (Apple Vision, on-device)
- Set `capture_type` to `whiteboard_ocr`
- Continue to step 12

## Widget Setup

1. Long-press home screen > Add Widget
2. Add Shortcuts widget
3. Select "Capture to Selene" shortcut
4. Also add to Lock Screen (iOS 16+)

## Configuration

Replace these values before use:

| Variable | Where to get it |
|----------|----------------|
| `YOUR_CLAUDE_API_KEY` | console.anthropic.com > API Keys |
| `YOUR_TAILSCALE_IP` | Tailscale app > your Mac's IP |
| `YOUR_SELENE_TOKEN` | Your `.env` file, `SELENE_AUTH_TOKEN` value |

## Testing

1. **Whiteboard test**: Point camera at a whiteboard with writing > verify note appears in Selene with `capture_type: whiteboard`
2. **Paper test**: Photograph a handwritten note > verify interpretation quality
3. **Share Sheet test**: Open Photos > select image > Share > "Capture to Selene"
4. **Daily sheet test**: Photograph an annotated daily planning sheet > verify `capture_type: daily_sheet_annotation`
5. **Offline test**: Enable airplane mode > capture > verify Apple Vision fallback fires

## Cost

~$0.006 per capture with Haiku 3.5. At 10 captures/day: under $2/month.
