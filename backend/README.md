# FastAPI Backend

## Install

```bash
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## Environment Variables

Create a `.env` file in the `backend` directory if you want to override defaults.

```env
APP_NAME=Start On API
APP_VERSION=0.1.0
APP_ENV=development
LOG_LEVEL=INFO
API_HOST=0.0.0.0
API_PORT=8000
API_RELOAD=false
API_V1_PREFIX=/api/v1
WEB_CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key
SUPABASE_ANON_KEY=your-supabase-anon-key
GEMINI_API_KEY=your-gemini-api-key
GEMINI_MODEL_NAME=gemini-3.5-flash
GEMINI_THINKING_LEVEL=low
GEMINI_MAX_OUTPUT_TOKENS=2048
NOTION_TOKEN_ENCRYPTION_KEY=your-fernet-key-generated-by-cryptography-fernet
```

The backend reads `backend/.env` even if the server is started from the project root.

Required at startup:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `NOTION_TOKEN_ENCRYPTION_KEY`

`NOTION_TOKEN_ENCRYPTION_KEY` must be a non-empty Fernet key in the format expected by `cryptography.fernet.Fernet`, which is a URL-safe base64-encoded 32-byte key. A valid example can be generated with:

```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Optional unless you use the related feature:
- `GEMINI_API_KEY`
- `GEMINI_MODEL_NAME` (default: `gemini-3.5-flash`)
- `GEMINI_THINKING_LEVEL` (default: `low`; set empty to use the model default)
- `GEMINI_MAX_OUTPUT_TOKENS` (default: `2048`)

For the AI task suggestion flow, keep `GEMINI_MODEL_NAME` on a stable model such as
`gemini-3.5-flash` unless you intentionally want to test a preview model. Lower
`GEMINI_THINKING_LEVEL` values reduce latency for short task-planning prompts.

Notion tokens are encrypted before being stored on the server.

For browser-based clients such as the Vercel-hosted Flutter web app, set
`WEB_CORS_ALLOWED_ORIGINS` to a comma-separated list of allowed origins.
Example:

```env
WEB_CORS_ALLOWED_ORIGINS=https://your-app.vercel.app,https://your-preview.vercel.app
```

On Railway, the platform-provided `PORT` environment variable is also accepted,
so you do not need to hardcode `API_PORT` for production.

## Run

Run the command inside the `backend` directory.

```bash
.\.venv\Scripts\python.exe -m app.main
```

If you prefer `uvicorn` directly, use:

```bash
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Or use the included launcher:

```bash
.\run_backend.ps1
```

Windows note:

- If an existing `.venv` was copied or the project folder was renamed, recreate the virtual environment before installing again.
- In some Windows environments, `--reload` can fail during Uvicorn's reloader startup with `PermissionError: [WinError 5]`.
- If that happens, keep `API_RELOAD=false` and run without `--reload`.
- Do not run bare `python` or bare `uvicorn` if your shell resolves to `C:\msys64\ucrt64\bin\python.exe` or `C:\msys64\ucrt64\bin\uvicorn.exe`.
- Prefer `.\.venv\Scripts\python.exe -m pip ...` instead of `pip ...` so the interpreter and installer always match.
- If you see `C:\msys64\...` in the traceback, you are not using the project virtual environment.

Open:

- `http://127.0.0.1:8000/docs`
- `http://127.0.0.1:8000/redoc`

Android emulator note:

- The Flutter app uses `http://10.0.2.2:8000` by default.
- That only works when the backend is running on your PC and listening on `0.0.0.0:8000`.
- If the server is bound to `127.0.0.1` only, the emulator will show `SocketException: Connection refused`.

## API Examples

### Health Check

Request:

```bash
curl http://127.0.0.1:8000/api/v1/health
```

Response:

```json
{
  "success": true,
  "data": {
    "status": "ok",
    "app_name": "Start On API",
    "environment": "development",
    "version": "0.1.0"
  },
  "error": null
}
```

### Quest Generation

Request:

```bash
curl -X POST http://127.0.0.1:8000/api/v1/quests/generate \
  -H "Content-Type: application/json" \
  -d "{\"prompt\":\"Prepare project presentation\",\"difficulty\":\"hard\",\"category\":\"work\",\"max_items\":3}"
```

Response:

```json
{
  "success": true,
  "data": {
    "quests": [
      {
        "title": "Prepare project presentation",
        "difficulty": "hard",
        "category": "work",
        "exp": 100,
        "defaultDurationSeconds": 5400,
        "reason": "Applied explicit difficulty. Applied explicit category."
      }
    ]
  },
  "error": null
}
```

### OCR Text Quest Extraction

Request:

```bash
curl -X POST http://127.0.0.1:8000/api/v1/quests/from-text \
  -H "Content-Type: application/json" \
  -d "{\"raw_text\":\"- Buy groceries\n- Buy groceries\n- Clean kitchen\n1234\nStudy chapter 3\"}"
```

Response:

```json
{
  "success": true,
  "data": {
    "quests": [
      {
        "title": "Buy groceries",
        "difficulty": "easy",
        "category": "home",
        "exp": 30,
        "defaultDurationSeconds": 1500,
        "reason": "Generated from cleaned OCR text."
      },
      {
        "title": "Clean kitchen",
        "difficulty": "easy",
        "category": "home",
        "exp": 30,
        "defaultDurationSeconds": 1500,
        "reason": "Generated from cleaned OCR text."
      },
      {
        "title": "Study chapter 3",
        "difficulty": "normal",
        "category": "study",
        "exp": 50,
        "defaultDurationSeconds": 2700,
        "reason": "Generated from cleaned OCR text."
      }
    ],
    "cleaned_lines": [
      "Buy groceries",
      "Clean kitchen",
      "Study chapter 3"
    ],
    "duplicate_removed_count": 1
  },
  "error": null
}
```

### Notion Sync

Behavior note:

- New Notion sync rows are deduplicated only by `(user_id, external_source, external_id)`.
- Legacy Notion-imported quest rows with null `external_source` or `external_id` are not auto-merged by title.
- This means the first sync after upgrading can leave a legacy row and a new external-id-backed row side by side for the same apparent task. That is intentional to avoid ambiguous overwrite of older data.

Request:

```bash
curl -X POST http://127.0.0.1:8000/api/v1/integrations/notion/sync \
  -H "Content-Type: application/json" \
  -d "{\"notion_api_token\":\"secret_xxx\",\"database_url\":\"https://www.notion.so/your-workspace/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}"
```

Response:

```json
{
  "success": true,
  "data": {
    "database_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "database_title": "My Notion Tasks",
    "quests": [
      {
        "title": "Prepare weekly report",
        "difficulty": "normal",
        "category": "work",
        "exp": 50,
        "defaultDurationSeconds": 2700,
        "reason": "Generated from Notion sync."
      }
    ]
  },
  "error": null
}
```

## Structure

- `app/main.py`: FastAPI entry point
- `app/api/routes`: Route handlers
- `app/schemas`: Request and response models
- `app/services`: Business logic layer
- `app/repositories`: persistence abstractions and future Supabase-backed implementations
- `app/providers`: External integration and generation providers
- `app/core`: App settings and bootstrap-related modules

Several endpoints are still placeholder-backed with mock repositories so the API surface is ready before the Supabase implementations are completed.
