IF OBJECT_ID(N'dbo.login_otp_codes', N'U') IS NULL
BEGIN
    CREATE TABLE login_otp_codes (
        id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
        user_id UNIQUEIDENTIFIER NOT NULL REFERENCES users(id),
        code_hash NVARCHAR(128) NOT NULL,
        expires_at DATETIME2 NOT NULL,
        attempt_count INT NOT NULL DEFAULT 0,
        used_at DATETIME2 NULL,
        created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_login_otp_codes_user_expires_at' AND object_id = OBJECT_ID(N'dbo.login_otp_codes'))
    CREATE INDEX ix_login_otp_codes_user_expires_at ON login_otp_codes(user_id, expires_at);
