# User Guide: Account Settings

This guide explains how to manage your Tabula account, including profile settings, password
management, and account deletion.

## Table of Contents

- [Accessing Account Settings](#accessing-account-settings)
- [Profile Management](#profile-management)
- [Password Management](#password-management)
- [Account Plan](#account-plan)
- [Account Deletion](#account-deletion)
- [Privacy & Security](#privacy--security)

## Accessing Account Settings

You can access your account settings from the browser extension:

1. Click the **Tabula** extension icon in your browser toolbar
2. Click the **Settings** icon (⚙️) in the top-right corner
3. The Account Settings modal will open

## Profile Management

### Viewing Your Profile

Your profile displays the following information:

- **Profile Picture**: Generated from your initials
- **Name**: Your full name
- **Email**: Your email address (cannot be changed)
- **Account Plan**: Your current tier (Free, Pro, or Team)

### Updating Your Name

1. In Account Settings, locate the "User Information" section
2. Click the **Edit** icon (✏️) next to your name
3. Enter your new name
4. Click **Save**
5. Click **Cancel** to discard changes

Your name will be updated across all devices immediately.

### Profile Picture

Currently, profile pictures are automatically generated from your initials. Custom profile pictures
will be available in a future update.

## Password Management

Tabula uses WorkOS AuthKit for secure authentication. This means your password is managed by our
enterprise-grade authentication provider, not stored directly in Tabula.

### Changing Your Password

1. In Account Settings, locate the "Password" section
2. Click the **Change Password** button
3. You'll be redirected to our secure authentication provider (WorkOS)
4. Follow the prompts to change your password
5. The window will close automatically when complete

### Password Reset

If you've forgotten your password:

1. On the login screen, click **Forgot Password**
2. Enter your email address
3. Check your email for a password reset link
4. Follow the link to create a new password
5. Return to Tabula and log in with your new password

### Password Requirements

- Minimum 8 characters
- Must contain at least one uppercase letter
- Must contain at least one lowercase letter
- Must contain at least one number
- Special characters recommended but not required

## Account Plan

### Current Plan

Your current plan is displayed in the Account Settings under "User Information". Tabula offers three
tiers:

**Free Tier**:

- Up to 10 workspaces
- Unlimited tabs per workspace
- Local storage with cloud sync
- Single user account

**Pro Tier** (Coming Soon):

- Up to 50 workspaces
- Priority support
- Advanced features
- Cloud backup with history

**Team Tier** (Coming Soon):

- Unlimited workspaces
- Team collaboration
- Admin controls
- SSO integration

### Upgrading Your Plan

Plan upgrades will be available in a future update. We'll notify you when this feature launches.

## Account Deletion

### Deleting Your Account

> **⚠️ Warning**: Account deletion is permanent and cannot be undone. All your data will be
> permanently deleted.

To delete your account:

1. In Account Settings, scroll to the "Danger Zone" section
2. Click the **Delete Account** button
3. Read the warning message carefully
4. Click **Delete My Account** to confirm
5. You'll be logged out and all your data will be deleted

### What Gets Deleted

When you delete your account, the following data is permanently removed:

- Your user profile
- All workspaces and space groups
- All tabs and tab history
- All resources, notes, and tasks
- All backups
- All session data

### Before You Delete

Consider these alternatives:

- **Export your data**: Download your workspaces before deletion (feature coming soon)
- **Take a break**: Just log out and come back later
- **Contact support**: Reach out if you're having issues

## Privacy & Security

### Data Collection

Tabula collects the minimum data necessary to provide our service:

- Email address (for authentication)
- Name (for personalization)
- Workspace and tab data (for sync)
- Usage statistics (anonymous)

We never:

- Sell your data to third parties
- Share your personal information without consent
- Track your browsing history outside of Tabula

### Security Features

- **Enterprise-grade authentication**: Powered by WorkOS AuthKit
- **Encrypted connections**: All data transmitted over HTTPS
- **Secure storage**: Passwords hashed with bcrypt
- **Regular security audits**: We regularly review our security practices

### Session Management

Your session is automatically managed:

- **Token expiration**: Access tokens expire after 15 minutes
- **Automatic refresh**: Tokens refresh automatically while you're active
- **Secure storage**: Tokens stored in Chrome's secure local storage
- **Multi-device support**: Log in on multiple devices simultaneously

### Logout

To log out:

1. Click the **Logout** button in the extension popup
2. Your local session will be cleared
3. You'll need to log in again to access your data

You'll remain logged in on other devices unless you log out there as well.

## Frequently Asked Questions

### Can I change my email address?

Email address changes are not currently supported. Your email address is used as your unique
identifier. If you need to change your email, please contact support.

### Can I have multiple accounts?

Yes, but you can only be logged into one account at a time in the extension. You can log out and log
in with a different account.

### What happens to my data when I log out?

Your local data remains cached on your device. When you log back in, it will sync with your cloud
data. If you want to completely remove local data, delete your account or clear the extension data
from browser settings.

### Can I recover a deleted account?

No. Account deletion is permanent. We recommend exporting your data before deletion (feature coming
soon).

### How do I report a security issue?

If you discover a security vulnerability, please report it to us at security@tabula.app. Do not
disclose security issues publicly.

### Is my browsing history visible to Tabula?

No. Tabula only knows about tabs you explicitly save to workspaces. We don't track your general
browsing history.

## Support

Need help? Contact us:

- **Email**: support@tabula.app
- **GitHub Issues**:
  [github.com/VitruvianSoftware/vitruvian-core/issues](https://github.com/VitruvianSoftware/vitruvian-core/issues)
- **Documentation**: [docs.tabula.app](https://docs.tabula.app)

---

_Last updated: December 2024_
