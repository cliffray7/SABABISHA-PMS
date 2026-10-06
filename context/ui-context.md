## Activity screens

- Admin platform activity follows a compact, card-based layout: page header, search + organization/date controls, range selector, filter chips, and data table/timeline rows.
- The activity view should use a clean purple accent palette for active filter pills and keep controls aligned with the platform admin shell.
- Date filters must never send a future range or a range wider than 366 days. Omit the upper bound for live ranges and custom ranges ending today to avoid client/server clock skew; clamp custom ranges to the supported 366-day window.
- The SuperAdmin activity feed includes platform-scoped registration and authentication events; label their scope as Platform and do not expose them in organization activity feeds.
- Mobile login, registration, and OTP screens should share the web auth brand (TaskFlow), headings, descriptions, purple accent, compact bordered card, and OTP expiry/resend behavior while retaining touch-friendly stacked fields.
- Web brand surfaces (landing, auth, workspace/admin sidebars, development email preview, and favicon) use the supplied Figma `Primary lockup.svg` and `Mobile launcher.svg` assets from `apps/web/public`.
- The mobile app launcher uses the TaskFlow wordmark as its display name and the symbol/colors from `Mobile launcher.svg` for Android adaptive and legacy icons.
