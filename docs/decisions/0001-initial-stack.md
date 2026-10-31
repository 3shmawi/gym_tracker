# 0001 — Initial stack

Date: 2026-10-31 · Status: accepted

| Area | Choice |
|---|---|
| Environments | staging, prod |
| Architecture | Layered clean architecture (data + domain + presentation, use cases) |
| State management | Riverpod (Notifier) |
| Backend | Supabase |
| Monitoring | Sentry |
| Analytics & feature flags | PostHog (no Firebase) |
| CI/CD | GitHub Actions (public repository) |
| Routing / deep links | go_router |
| Localization | Arabic + English, RTL |

## Why
<!-- Fill in from the idea discussion: app size, expected complexity, team,
     why this architecture and state management fit. -->

## Revisit when
<!-- e.g. "the app gets offline sync" or "more than one developer joins". -->
