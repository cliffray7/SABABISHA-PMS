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
    public DbSet<Comment> Comments => Set<Comment>();
    public DbSet<CommentMention> CommentMentions => Set<CommentMention>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<Notification> Notifications => Set<Notification>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
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
        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("users");
            entity.HasKey(user => user.Id);
            entity.HasIndex(user => user.Email).IsUnique();
            entity.Property(user => user.Email).HasMaxLength(320).IsRequired();
            entity.Property(user => user.PasswordHash).HasMaxLength(500).IsRequired();
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
            entity.HasIndex(member => new { member.OrganizationId, member.UserId }).IsUnique();
            entity.HasIndex(member => new { member.UserId, member.Status });
        });

        modelBuilder.Entity<OrganizationInvitation>(entity =>
        {
            entity.ToTable("organization_invitations");
            entity.HasKey(invitation => invitation.Id);
            entity.HasIndex(invitation => invitation.TokenHash).IsUnique();
            entity.HasIndex(invitation => new { invitation.OrganizationId, invitation.Email });
        });

        modelBuilder.Entity<Project>(entity =>
        {
            entity.ToTable("projects");
            entity.HasKey(project => project.Id);
            entity.HasIndex(project => project.OrganizationId);
            entity.Property(project => project.Name).HasMaxLength(200).IsRequired();
        });

        modelBuilder.Entity<ProjectMember>(entity =>
        {
            entity.ToTable("project_members");
            entity.HasKey(member => member.Id);
            entity.HasIndex(member => new { member.ProjectId, member.UserId }).IsUnique();
            entity.HasIndex(member => new { member.UserId, member.Status });
        });

        modelBuilder.Entity<WorkTask>(entity =>
        {
            entity.ToTable("tasks");
            entity.HasKey(task => task.Id);
            entity.HasIndex(task => new { task.ProjectId, task.Status });
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
            entity.HasIndex(assignee => new { assignee.TaskId, assignee.UserId }).IsUnique();
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