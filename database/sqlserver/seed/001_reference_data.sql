-- Reference seed data is intentionally idempotent.
-- User passwords must be created through /api/v1/auth/register so only hashed values are stored.

IF NOT EXISTS (SELECT 1 FROM organizations WHERE slug = 'demo')
BEGIN
    INSERT INTO organizations (id, name, slug, timezone)
    VALUES ('11111111-1111-1111-1111-111111111111', 'Demo Organization', 'demo', 'UTC');
END;
