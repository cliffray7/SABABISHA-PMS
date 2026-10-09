using Microsoft.EntityFrameworkCore;
using Pms.Domain.Entities;

namespace Pms.Infrastructure.Persistence.EfCore;

public sealed class PmsDbContext(DbContextOptions<PmsDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<PasswordResetToken> PasswordResetTokens => Set<PasswordResetToken>();
    public DbSet<LoginOtpCode> LoginOtpCodes => Set<LoginOtpCode>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Organization> Organizations => Set<Organization>();
    public DbSet<OrganizationMember> OrganizationMembers => Set<OrganizationMember>();
    public DbSet<OrganizationInvitation> OrganizationInvitations => Set<OrganizationInvitation>();
    public DbSet<Project> Projects => Set<Project>();
    public DbSet<ProjectMember> ProjectMembers => Set<ProjectMember>();
    public DbSet<WorkTask> Tasks => Set<WorkTask>();
    public DbSet<TaskAssignee> TaskAssignees => Set<TaskAssignee>();
    public DbSet<TaskAssignmentEvent> TaskAssignmentEvents => Set<TaskAssignmentEvent>();
    public DbSet<Comment> Comments => Set<Comment>();
    public DbSet<CommentMention> CommentMentions => Set<CommentMention>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<AdminAuditEvent> AdminAuditEvents => Set<AdminAuditEvent>();
    public DbSet<ActivityEvent> ActivityEvents => Set<ActivityEvent>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ActivityEvent>(entity =>
        {
            entity.ToTable("activity_events");
            entity.HasKey(activity => activity.Id);
            entity.Property(activity => activity.ActorName).HasMaxLength(201).IsRequired();
            entity.Property(activity => activity.Category).HasMaxLength(40).IsRequired();
            entity.Property(activity => activity.Action).HasMaxLength(80).IsRequired();
            entity.Property(activity => activity.EntityType).HasMaxLength(40).IsRequired();
            entity.Property(activity => activity.EntityName).HasMaxLength(300).IsRequired();
            entity.Property(activity => activity.Description).HasMaxLength(500).IsRequired();
            entity.Property(activity => activity.Status).HasMaxLength(20).IsRequired();
            entity.Property(activity => activity.CorrelationId).HasMaxLength(128).IsRequired();
            entity.HasIndex(activity => new { activity.OrganizationId, activity.CreatedAtUtc, activity.Id });
            entity.HasIndex(activity => new { activity.OrganizationId, activity.ProjectId, activity.CreatedAtUtc });
            entity.HasIndex(activity => new { activity.OrganizationId, activity.Category, activity.CreatedAtUtc });
            entity.HasIndex(activity => new { activity.OrganizationId, activity.ActorUserId, activity.CreatedAtUtc });
            entity.HasIndex(activity => new { activity.OrganizationId, activity.EntityType, activity.EntityId });
        });

        modelBuilder.Entity<AdminAuditEvent>(entity =>
        {
            entity.ToTable("admin_audit_events");
            entity.HasKey(auditEvent => auditEvent.Id);
            entity.Property(auditEvent => auditEvent.ActorDisplayName).HasMaxLength(201).IsRequired();
            entity.Property(auditEvent => auditEvent.Action).HasMaxLength(80).IsRequired();
            entity.Property(auditEvent => auditEvent.TargetType).HasMaxLength(80).IsRequired();
            entity.Property(auditEvent => auditEvent.TargetDisplayName).HasMaxLength(300).IsRequired();
            entity.Property(auditEvent => auditEvent.Outcome).HasMaxLength(20).IsRequired();
            entity.Property(auditEvent => auditEvent.Reason).HasMaxLength(500);
            entity.Property(auditEvent => auditEvent.CorrelationId).HasMaxLength(128).IsRequired();
            entity.HasIndex(auditEvent => new { auditEvent.OccurredAt, auditEvent.Id });
            entity.HasIndex(auditEvent => new { auditEvent.ActorId, auditEvent.OccurredAt });
            entity.HasIndex(auditEvent => new { auditEvent.Action, auditEvent.OccurredAt });
            entity.HasIndex(auditEvent => new { auditEvent.TargetType, auditEvent.TargetId, auditEvent.OccurredAt });
        });

        modelBuilder.Entity<PasswordResetToken>(entity =>
        {
            entity.ToTable("password_reset_tokens");
            entity.HasKey(x => x.Id);
            entity.HasIndex(x => x.TokenHash).IsUnique();
            entity.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.NoAction);
        });
        modelBuilder.Entity<LoginOtpCode>(entity =>
        {
            entity.ToTable("login_otp_codes", tb => tb.UseSqlOutputClause(false));
            entity.HasKey(x => x.Id);
            entity.HasIndex(x => new { x.UserId, x.ExpiresAt });
            entity.Property(x => x.CodeHash).HasMaxLength(128).IsRequired();
            entity.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.NoAction);
        });
        modelBuilder.Entity<ProjectMember>().HasOne<Project>().WithMany().HasForeignKey(x => x.ProjectId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<CommentMention>().HasOne<Comment>().WithMany().HasForeignKey(x => x.CommentId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<Project>().HasMany<WorkTask>().WithOne().HasForeignKey(task => task.ProjectId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<WorkTask>().HasOne<WorkTask>().WithMany().HasForeignKey(task => task.ParentTaskId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<Comment>().HasOne<Comment>().WithMany().HasForeignKey(comment => comment.ParentCommentId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<Comment>().HasOne<WorkTask>().WithMany().HasForeignKey(comment => comment.TaskId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<Attachment>().HasOne<WorkTask>().WithMany().HasForeignKey(attachment => attachment.TaskId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<Attachment>().HasOne<Comment>().WithMany().HasForeignKey(attachment => attachment.CommentId).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<Attachment>().HasOne<User>().WithMany().HasForeignKey(attachment => attachment.UploadedBy).OnDelete(DeleteBehavior.NoAction);
        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("users");
            entity.HasKey(user => user.Id);
            entity.HasIndex(user => user.Email).IsUnique();
            entity.Property(user => user.Email).HasMaxLength(320).IsRequired();
            entity.Property(user => user.PasswordHash).HasMaxLength(500).IsRequired();
            entity.Property(user => user.AvatarUrl).HasMaxLength(2000);
            entity.Property(user => user.AvatarPublicId).HasMaxLength(500);
        });

        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.ToTable("refresh_tokens");
            entity.HasKey(token => token.Id);
            entity.HasIndex(token => token.TokenHash).IsUnique();
            entity.HasIndex(token => new { token.UserId, token.ExpiresAt });
            entity.HasOne<User>().WithMany().HasForeignKey(token => token.UserId)
                .OnDelete(DeleteBehavior.NoAction);
        });

        modelBuilder.Entity<Organization>(entity =>
        {
            entity.ToTable("organizations");
            entity.HasKey(organization => organization.Id);
            entity.HasIndex(organization => organization.Name).IsUnique();
            entity.HasIndex(organization => organization.Slug).IsUnique();
            entity.Property(organization => organization.Name).HasMaxLength(200).IsRequired();
            entity.Property(organization => organization.Slug).HasMaxLength(200).IsRequired();
            entity.HasMany(organization => organization.Members)
                .WithOne(member => member.Organization)
                .HasForeignKey(member => member.OrganizationId);
        });

        modelBuilder.Entity<OrganizationMember>(entity =>
        {
            entity.ToTable("organization_members");
            entity.HasKey(member => member.Id);
            entity.HasIndex(member => new { member.OrganizationId, member.UserId }).IsUnique().HasDatabaseName("uq_organization_members");
            entity.HasIndex(member => new { member.UserId, member.Status }).HasDatabaseName("ix_organization_members_user_status");
        });

        modelBuilder.Entity<OrganizationInvitation>(entity =>
        {
            // The deployed table has an audit trigger. SQL Server does not allow
            // EF Core's default UPDATE ... OUTPUT form on trigger-backed tables.
            entity.ToTable("organization_invitations", table => table.UseSqlOutputClause(false));
            entity.HasKey(invitation => invitation.Id);
            entity.HasIndex(invitation => invitation.TokenHash).IsUnique();
            entity.HasIndex(invitation => new { invitation.OrganizationId, invitation.Email });
        });

        modelBuilder.Entity<Project>(entity =>
        {
            entity.ToTable("projects");
            entity.HasKey(project => project.Id);
            entity.HasAlternateKey(project => new { project.Id, project.OrganizationId });
            entity.HasIndex(project => project.OrganizationId);
            entity.Property(project => project.Name).HasMaxLength(200).IsRequired();
        });

        modelBuilder.Entity<ProjectMember>(entity =>
        {
            entity.ToTable("project_members");
            entity.HasKey(member => member.Id);
            entity.HasIndex(member => new { member.ProjectId, member.UserId }).IsUnique().HasDatabaseName("uq_project_members");
            entity.HasIndex(member => new { member.UserId, member.Status }).HasDatabaseName("ix_project_members_user_status");
        });

        modelBuilder.Entity<WorkTask>(entity =>
        {
            entity.ToTable("tasks");
            entity.HasKey(task => task.Id);
            entity.HasAlternateKey(task => new { task.Id, task.ProjectId });
            entity.HasIndex(task => new { task.ProjectId, task.Status }).HasDatabaseName("ix_tasks_project_status");
            entity.Property(task => task.Title).HasMaxLength(300).IsRequired();
            entity.Property(task => task.Status).HasMaxLength(40).IsRequired();
            entity.Property(task => task.Priority).HasMaxLength(20).IsRequired();
            entity.HasMany(task => task.Assignees)
                .WithOne(assignee => assignee.Task)
                .HasForeignKey(assignee => assignee.TaskId);
        });

        modelBuilder.Entity<TaskAssignee>(entity =>
        {
            entity.ToTable("task_assignees");
            entity.HasKey(assignee => assignee.Id);
            entity.HasIndex(assignee => new { assignee.TaskId, assignee.UserId }).IsUnique().HasDatabaseName("uq_task_assignees");
            entity.HasIndex(assignee => new { assignee.UserId, assignee.Status }).HasDatabaseName("ix_task_assignees_user_status");
        });

        modelBuilder.Entity<TaskAssignmentEvent>(entity =>
        {
            entity.ToTable("task_assignment_events", table => table.HasCheckConstraint(
                "ck_task_assignment_events_action_replacement_reason",
                "(action = 'REASSIGNED' AND replacement_user_id IS NOT NULL AND replacement_user_id <> departing_user_id AND reason_code IS NULL) OR " +
                "(action = 'UNASSIGNED' AND replacement_user_id IS NULL AND reason_code IS NULL) OR " +
                "(action = 'LIFECYCLE_INACTIVATED' AND replacement_user_id IS NULL AND reason_code IS NOT NULL AND reason_code IN ('PROJECT_ARCHIVED', 'PROJECT_TRASHED', 'PROJECT_TRASH_EXPIRED'))"));
            entity.HasKey(item => item.EventId);
            entity.Property(item => item.Action).HasMaxLength(32).IsRequired();
            entity.Property(item => item.ReasonCode).HasMaxLength(40);
            entity.HasOne<Organization>().WithMany().HasForeignKey(item => item.OrganizationId)
                .OnDelete(DeleteBehavior.NoAction);
            entity.HasOne<Project>().WithMany()
                .HasForeignKey(item => new { item.ProjectId, item.OrganizationId })
                .HasPrincipalKey(project => new { project.Id, project.OrganizationId })
                .OnDelete(DeleteBehavior.NoAction);
            entity.HasOne<WorkTask>().WithMany()
                .HasForeignKey(item => new { item.TaskId, item.ProjectId })
                .HasPrincipalKey(task => new { task.Id, task.ProjectId })
                .OnDelete(DeleteBehavior.NoAction);
            entity.HasOne<User>().WithMany().HasForeignKey(item => item.DepartingUserId)
                .OnDelete(DeleteBehavior.NoAction);
            entity.HasOne<User>().WithMany().HasForeignKey(item => item.ActorUserId)
                .OnDelete(DeleteBehavior.NoAction);
            entity.HasOne<User>().WithMany().HasForeignKey(item => item.ReplacementUserId)
                .OnDelete(DeleteBehavior.NoAction);
            entity.HasIndex(item => new { item.TaskId, item.OccurredAtUtc, item.EventId });
            entity.HasIndex(item => new { item.ProjectId, item.OrganizationId, item.TaskId });
            entity.HasIndex(item => new { item.OperationId, item.EventId });
            entity.HasIndex(item => item.DepartingUserId);
            entity.HasIndex(item => item.ActorUserId);
            entity.HasIndex(item => item.ReplacementUserId).HasFilter("replacement_user_id IS NOT NULL");
        });

        modelBuilder.Entity<Comment>(entity =>
        {
            entity.ToTable("comments");
            entity.HasKey(comment => comment.Id);
            entity.HasIndex(comment => new { comment.TaskId, comment.CreatedAt });
            entity.Property(comment => comment.Content).HasMaxLength(10000).IsRequired();
        });

        modelBuilder.Entity<CommentMention>(entity =>
        {
            entity.ToTable("comment_mentions");
            entity.HasKey(mention => mention.Id);
            entity.HasIndex(mention => new { mention.CommentId, mention.UserId }).IsUnique();
        });

        modelBuilder.Entity<Attachment>(entity =>
        {
            entity.ToTable("attachments");
            entity.HasKey(attachment => attachment.Id);
            entity.HasIndex(attachment => attachment.TaskId);
            entity.HasIndex(attachment => attachment.CommentId);
            entity.Property(attachment => attachment.FileName).HasMaxLength(500).IsRequired();
            entity.Property(attachment => attachment.FileUrl).HasMaxLength(2000).IsRequired();
            entity.Property(attachment => attachment.CloudinaryPublicId).HasMaxLength(500);
            entity.Property(attachment => attachment.CloudinaryResourceType).HasMaxLength(20);
        });

        modelBuilder.Entity<Notification>(entity =>
        {
            entity.ToTable("notifications");
            entity.HasKey(notification => notification.Id);
            entity.HasIndex(notification => new { notification.UserId, notification.IsRead, notification.CreatedAt });
            entity.Property(notification => notification.Message).HasMaxLength(2000).IsRequired();
        });

        // The SQL setup scripts use snake_case column names throughout.
        foreach (var entity in modelBuilder.Model.GetEntityTypes())
        foreach (var property in entity.GetProperties())
        {
            var columnName = System.Text.RegularExpressions.Regex.Replace(
                property.Name, "([a-z0-9])([A-Z])", "$1_$2").ToLowerInvariant();
            property.SetColumnName(columnName);
        }
    }
}
