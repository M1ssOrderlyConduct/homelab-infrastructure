# Notion MCP Integration for Open WebUI

**Source:** Open WebUI Documentation
**Saved:** 2026-01-20

## Overview
Enables Open WebUI to interact with Notion workspace using Model Context Protocol (MCP):
- Search pages, read content, create docs, manage databases
- Automatic Markdown conversion for better LLM comprehension

## Method 1: Streamable HTTP (Recommended)

Connects directly to `https://mcp.notion.com/mcp` using OAuth.

### Prerequisites
- Set `WEBUI_SECRET_KEY` environment variable (persistent value required for OAuth sessions)

### Configuration JSON
```json
[
  {
    "type": "mcp",
    "url": "https://mcp.notion.com/mcp",
    "spec_type": "url",
    "spec": "",
    "path": "openapi.json",
    "auth_type": "oauth_2.1",
    "key": "",
    "info": {
      "id": "ntn",
      "name": "Notion",
      "description": "A note-taking and collaboration platform"
    }
  }
]
```

### Setup Steps
1. Admin Panel > Settings > External Tools > + > Import JSON
2. Click "Register Client" button
3. Save
4. In chat: + > Integrations > Tools > Toggle Notion ON
5. Authorize via "Connect with Notion MCP" screen

## Method 2: Self-Hosted via MCPO (Advanced)

For running MCP server locally within infrastructure.

### Prerequisites
- Create Internal Integration in Notion to get Secret Key
- MCPO bridge container

### MCPO Configuration (Node.js)
```json
{
  "mcpServers": {
    "notion": {
      "command": "npx",
      "args": ["-y", "@notionhq/notion-mcp-server"],
      "env": {
        "NOTION_TOKEN": "secret_YOUR_KEY_HERE"
      }
    }
  }
}
```

### MCPO Configuration (Docker)
```json
{
  "mcpServers": {
    "notion": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "-e", "NOTION_TOKEN", "mcp/notion"],
      "env": {
        "NOTION_TOKEN": "secret_YOUR_KEY_HERE"
      }
    }
  }
}
```

### Open WebUI Connection JSON (for MCPO)
```json
[
  {
    "type": "openapi",
    "url": "http://<YOUR_MCPO_IP>:<PORT>/notion",
    "spec_type": "url",
    "spec": "",
    "path": "openapi.json",
    "auth_type": "none",
    "info": {
      "id": "notion-local",
      "name": "Notion (Local)",
      "description": "Local Notion integration via MCPO"
    }
  }
]
```

## Creating Internal Integration

1. Go to: https://www.notion.so/my-integrations
2. Click "+ New integration"
3. Fill in:
   - Name: "Open WebUI MCP"
   - Workspace: Select target workspace
   - Type: **Internal** (required)
4. Save
5. Copy the "Internal Integration Secret"
6. Configure Capabilities:
   - Read content
   - Update content
   - Insert content
   - (Optional) Read user information

### Granting Page Access

**Method A: Centralized (Recommended)**
- Integration dashboard > Access tab > Edit access
- Select pages to grant access

**Method B: Per-Page**
- On each Notion page: ... menu > Connections > Add your integration

## Rate Limits
- General: 180 requests/minute (3 req/sec)
- Search: 30 requests/minute

## Troubleshooting

### "Failed to connect to MCP server 'ntn'"
- OAuth session expired
- Fix: Toggle Notion switch ON again to re-authenticate

### "OAuth callback failed: mismatching_state"
- Accessing via localhost but WEBUI_URL is set to domain
- Fix: Access via the exact WEBUI_URL domain

### "Object not found"
- Page not shared with integration
- Fix: Grant page access in Integration settings or page Connections

### "missing_property when creating page"
- No parent specified
- Fix: Search for parent page first, get ID, then create inside it

### RateLimitedError (429)
- Exceeded API limits
- Fix: Perform actions sequentially, not in parallel

## Building a Notion Agent (Optional)

### System Prompt for Notion Assistant
```
You are a Notion workspace assistant with MCP tools. When users ask about their notes:
1. ALWAYS search first to find the relevant page
2. Read the page content before answering
3. For creating content, always specify a parent page
4. Be specific about which workspace/pages you're accessing
```

### Recommended Model Settings
- Tools: Enable Notion
- Knowledge: Add Notion MCP documentation for better tool understanding
