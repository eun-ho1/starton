# Start On Deployment Guide

## Architecture

- Frontend: `frontend/` Flutter Web, deployed to Vercel
- Backend: `backend/` FastAPI, deployed to Railway
- Database/Auth: Supabase

## Backend on Railway

### 1. Create the Railway service

- Create a new Railway project from this repository.
- Set the service root directory to `backend`.
- Let Railway detect and build `backend/Dockerfile`.

### 2. Configure environment variables

Set these variables in Railway:

```env
APP_ENV=production
LOG_LEVEL=INFO
API_V1_PREFIX=/api/v1
WEB_CORS_ALLOWED_ORIGINS=https://your-app.vercel.app,https://your-preview.vercel.app
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key
SUPABASE_ANON_KEY=your-supabase-anon-key
NOTION_TOKEN_ENCRYPTION_KEY=your-fernet-key
GEMINI_API_KEY=your-gemini-api-key
```

Notes:

- Railway injects `PORT` automatically. The backend now accepts `PORT` without extra config.
- `GEMINI_API_KEY` is optional unless AI generation features are enabled.
- `WEB_CORS_ALLOWED_ORIGINS` must include the real Vercel production URL. Add preview URLs only if you want preview deployments to call the live backend directly.

### 3. Verify the backend

After deployment, verify:

- `https://your-railway-domain/api/v1/health`
- `https://your-railway-domain/docs`

## Frontend on Vercel

### 1. Create the Vercel project

- Import the same repository into Vercel.
- Set the project root directory to `frontend`.
- Set Framework Preset to `Other`.
- If you keep the Vercel project root at the repository root by mistake, the repository-level `vercel-build.sh` now forwards to `frontend/` and copies the final site back to `build/web`.

### 2. Configure build settings

Use these settings:

- Build Command: `bash ./vercel-build.sh`
- Output Directory: `build/web`
- Install Command: leave empty
- Preferred: keep Root Directory as `frontend`, so these paths stay local to the Flutter app.

### 3. Configure environment variables

Set this variable in Vercel:

```env
START_ON_API_BASE_URL=https://your-railway-domain/api/v1
```

This value is compiled into the Flutter web bundle through `--dart-define`.
If this variable is missing, `vercel-build.sh` now fails early with a clear message.

### 4. Redeploy after backend URL changes

If the Railway public URL changes, update `START_ON_API_BASE_URL` in Vercel and trigger a new deployment. Flutter Web will not pick up runtime env changes automatically after the build is complete.

## Deployment Checklist

- Railway backend responds on `/api/v1/health`
- Railway has all Supabase and Notion encryption secrets
- Railway `WEB_CORS_ALLOWED_ORIGINS` includes the Vercel domain
- Vercel `START_ON_API_BASE_URL` points to the Railway `/api/v1` base
- Vercel build output is `build/web`
- After production deploy, sign-in and one API-backed screen both succeed from the browser
- If a deploy starts failing after upgrading Flutter locally, clear the Vercel build cache or redeploy. The build script now refreshes the cached Flutter checkout automatically.
