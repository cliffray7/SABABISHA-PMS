## Activity screens

- Admin platform activity follows a compact, card-based layout: page header, search + organization/date controls, range selector, filter chips, and data table/timeline rows.
- The activity view should use a clean purple accent palette for active filter pills and keep controls aligned with the platform admin shell.
- Date filters must never send a future range or a range wider than 366 days; the frontend should clamp to the last 366 days when generating custom bounds.
