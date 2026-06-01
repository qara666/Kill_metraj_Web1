# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Kill Metraj is a courier-logistics dashboard for Yaposhka (a Kharkiv restaurant delivery operation). The backend continuously pulls order/courier data from an external Yaposhka dashboard API, geocodes addresses, computes delivery routes, and pushes live updates to the React frontend over WebSocket. The UI shows per-division order status, courier efficiency, financial settlements, route planning, and a map.

Comments, commit history, and most docs are in Russian. Code is versioned inline with `vNN.x` markers in comments rather than git tags.

## Commands

Run frontend and backend from their own directories (`frontend/`, `backend/`) — each has its own `package.json` and `node_modules`. The root `package.json` is a thin convenience wrapper; prefer the per-app commands below.

**Backend** (`cd backend`):
- `npm run dev` — nodemon + `simple_server.js` (dev, auto-reload). Listens on `PORT` (default 5001).
- `npm start` — production via pm2 (`ecosystem.config.js`).
- `npm test` — jest. Run a single test: `npx jest path/to/file.test.js -t "test name"`.
- `npm run start:with-routing` — ensures the OSRM/Valhalla stack is up first, then starts.

**Frontend** (`cd frontend`):
- `npm run dev` — Vite dev server on port **5174** (strict). Proxies `/api` → `http://localhost:5001`.
- `npm run build` — `tsc && vite build`. Type errors fail the build.
- `npm run lint` — ESLint (`--max-warnings 0`).
- `npm test` — vitest. Single test: `npx vitest run src/path/file.test.ts`.

**Local dev (both at once):** `bash scripts/start_local.sh` (or `StartLocalDev.command` on macOS).

**E2E:** `npm run test:e2e` from root → Playwright (`tests/e2e`, baseURL defaults to `:10000`).

**Docker / deploy:** use the `Makefile` or `deploy.sh`. `make start` → prod stack; `make logs`, `make restart`, `make status`. `deploy.sh` subcommands: `start`, `start:prod`, `start:routing`, `start:cdc`, `start:full`. See `DOCKER_README.md` / `DOCKER_DEPLOY.md`.

## Architecture

### Backend (CommonJS, `backend/src` + `backend/workers`)

Entry point is `backend/simple_server.js` (~2000 lines) — it wires Express, Socket.io, PostgreSQL (Sequelize + a separate raw `pg` LISTEN client), the background workers, and the gRPC server. Most route registration and the `/api/turbo/*`, `/api/proxy/*`, `/api/robot/*` endpoints live directly in this file; resource CRUD lives in `src/routes/*` → `src/controllers/*`.

Layering is partially CQRS-style: `src/commands/` and `src/queries/` wrap some courier/dashboard operations on top of `src/models/` (Sequelize). `src/services/` holds cross-cutting logic (geocoding via Google/KML, analytics, caching, Telegram, routing health).

**Data flow (the core of the app):**
1. `workers/dashboardFetcher.js` polls the external Yaposhka API (`EXTERNAL_API_URL` + `EXTERNAL_API_KEY`) per division, with circuit breaker, rate limiting, ETag conditional requests, and UPSERT storage (one row per division/day) into PostgreSQL.
2. PostgreSQL `NOTIFY` fires on changes; `simple_server.js`'s `pgListenClient` (auto-reconnecting `LISTEN`) picks it up.
3. `workers/turboCalculator.js` ("TurboCalculator") groups orders into delivery runs, geocodes/validates coordinates (`turboGeoEnhanced.js`, `turboCoordValidator.js`, `turboGroupingHelpers.js`), and computes route distances via OSRM/Valhalla.
4. Results are cached (Redis, optional, via `CacheService`) and pushed to clients over Socket.io. The `/api/turbo/*` endpoints control and inspect this pipeline (`priority`, `stop`, `clear`, `status_today`, `reset-stale-routes`).

WebSocket auth: clients pass a JWT in the Socket.io handshake `auth.token`; verified in `io.use(...)`. REST auth is `authenticateToken` (Bearer JWT) in `src/middleware/auth.js`.

**Optional infrastructure** (each behind its own compose file under `backend/`): Redis cache (`REDIS_ENABLED`), Kafka + Debezium CDC (`docker-compose.debezium.yml`, `DashboardConsumer`), self-hosted OSRM/Valhalla routing (`docker-compose.routing.yml`), Nominatim/Photon geocoding (`docker-compose.selfhost.yml`). The app degrades gracefully when these are absent (falls back to remote/public providers and cache). gRPC server (`src/grpc/server.js`, proto in `backend/proto/service.proto`) runs on `GRPC_PORT` (50051).

### Frontend (`frontend/src`, React 18 + TypeScript + Vite)

- `App.tsx` — router; pages are `React.lazy`-loaded and prefetched on idle. Routes guarded by `ProtectedRoute`; admin pages under `pages/admin/`.
- State: **Zustand** stores in `src/stores/` (`useDashboardStore`, `useAutoPlannerStore`, `useRouteCalculationStore`) plus `src/store/` and React Query (`@tanstack/react-query`). React Context in `src/contexts/` for auth, theme, errors, and Excel-import data.
- `services/` is large and routing/geocoding-heavy: multiple interchangeable geocoders (`nominatimService`, `photonService`, `geoapifyService`, `dbGeocache`) and routers (`osrmService`, `valhallaService`, `YapikoOSRMService`, `RobustRoutingService`, `generouteService`). `socketService.ts` manages the live WebSocket connection; `api.ts` is the axios REST client. Map rendering uses Leaflet + Mapbox GL.
- Path alias `@` → `frontend/src`. Production builds drop `console.*`.

## Conventions & gotchas

- The two apps don't share a build or `tsconfig` — change them independently.
- `simple_server.js` uses several `global.*` stores (e.g. `global.divisionStatusStore`, `global.turboTodayCacheExists`) as cross-module state for the turbo pipeline. Be careful refactoring these.
- Routes are mounted under both `/api/v1/*` (newer) and `/api/*` (legacy); some resources answer on both. Check `simple_server.js` route registration before assuming a path.
- DB schema changes go through `backend/migrations/*.sql` (raw SQL, manually numbered). `DB_ALTER_SYNC` must stay `false` in production (Sequelize auto-alter is destructive).
- Required env (see `.env.server.example` / `backend/.env.example`): `DB_PASSWORD`, `JWT_SECRET`, `SEED_ADMIN_PASSWORD`, `EXTERNAL_API_KEY`, `EXTERNAL_API_URL`, `DOMAIN`. A seed admin is created on first boot from `SEED_ADMIN_*`.
- Many `reset_admin*.js`, `force_reset_admin.js`, `nuclear_reset_admin.js`, `inspect_*.js`, `test_*.js` files in `backend/` root are one-off operational/diagnostic scripts, not part of the app.
