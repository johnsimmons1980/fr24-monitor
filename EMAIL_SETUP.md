# FR24 Monitor Email Configuration

## Quick Setup

1. Copy the email template:
   ```bash
   cp email_config.template.json email_config.json
   ```

2. Edit `email_config.json` with your email settings, or use the web interface:
   - Visit: http://localhost:6869/config.php
   - Configure your SMTP settings
   - Test the email configuration

## Email Provider Settings

### Gmail
- SMTP Host: `smtp.gmail.com`
- Port: `587`
- Security: `TLS`
- Username: Your Gmail address
- Password: **Use an App Password, not your regular password**
- Setup App Password: Google Account → Security → 2-Step Verification → App passwords

### Outlook/Hotmail
- SMTP Host: `smtp-mail.outlook.com`
- Port: `587`
- Security: `TLS`
- Username: Your Outlook/Hotmail address
- Password: Your regular password (or app password if 2FA enabled)

### Yahoo
- SMTP Host: `smtp.mail.yahoo.com`
- Port: `587`
- Security: `TLS`
- Username: Your Yahoo address
- Password: **Use an App Password**

## Security Notes

- The `email_config.json` file is ignored by git to prevent password exposure
- Never commit email passwords to version control
- Use app passwords when available (more secure than regular passwords)
- The web interface at `/config.php` provides a user-friendly setup experience

## Testing

Test your email configuration:
```bash
./fr24_manager.sh test-email
```

This will send a simulated reboot alert to verify your settings work correctly.
