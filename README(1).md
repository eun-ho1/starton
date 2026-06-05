# Start On

Monorepo for the Start On frontend and backend.

## Structure

```text
start_on/
  frontend/   Flutter app
  backend/    FastAPI backend
  supabase/   Supabase local config and migrations
```

## Frontend

```bash
cd frontend
flutter run
```

## Backend

```bash
cd backend
py -3.11 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m app.main
```

Windows note:

- Prefer `.\.venv\Scripts\python.exe -m ...` over activating the environment and calling bare `python` or `pip`.
- This avoids accidentally using `C:\msys64\...` or another global Python interpreter.

## Deployment

- Frontend deployment guide: [docs/deployment_vercel_railway.md](/c:/mobile-programming/docs/deployment_vercel_railway.md)
- Recommended setup:
  - `frontend/` -> Vercel
  - `backend/` -> Railway
