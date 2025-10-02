# Security Policy

## Reporting a Vulnerability

The Bastion Aptos team takes security vulnerabilities seriously. We appreciate your efforts to responsibly disclose your findings.

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities by emailing:

**security@bastion-aptos.example.com** (replace with actual security contact)

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

### What to Include

Please include the following information in your report:

- Type of vulnerability
- Full paths of source file(s) related to the vulnerability
- Location of the affected source code (tag/branch/commit or direct URL)
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if available)
- Impact of the issue, including how an attacker might exploit it

### Response Process

1. **Acknowledgment**: We will acknowledge receipt of your vulnerability report within 48 hours.

2. **Assessment**: Our security team will assess the vulnerability and determine its impact and severity.

3. **Remediation**: We will work on a fix and prepare a security advisory if necessary.

4. **Disclosure**: We will coordinate with you on the disclosure timeline. We aim to disclose vulnerabilities within 90 days of the initial report.

5. **Credit**: We will credit you in the security advisory (unless you prefer to remain anonymous).

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |
| < 1.0   | :x:                |

We currently support only the latest version from the main branch. Once versioned releases are available, this table will be updated.

## Security Best Practices

### Smart Contract Security

- All Move contracts undergo internal review before deployment
- Consider external audits for major releases
- Follow Aptos Move security best practices
- Implement proper access controls and permission checks
- Test edge cases and failure scenarios

### Backend Security

- Keep dependencies up to date
- Use environment variables for sensitive configuration
- Implement rate limiting and input validation
- Follow OWASP security guidelines
- Use secure authentication and authorization

### Frontend Security

- Validate and sanitize user inputs
- Implement Content Security Policy (CSP)
- Use HTTPS for all communications
- Secure wallet integrations
- Protect against XSS and CSRF attacks

## Security Updates

Security updates will be announced through:
- GitHub Security Advisories
- Repository releases
- Project documentation

## Bug Bounty Program

Details about our bug bounty program (if available) will be published here when launched.

## Additional Resources

- [Aptos Security Best Practices](https://aptos.dev/guides/security)
- [OWASP Top Ten](https://owasp.org/www-project-top-ten/)
- [Move Security Guidelines](https://move-book.com/)

## Contact

For general security questions (non-vulnerabilities), please open a GitHub discussion or contact the maintainers.

---

Last Updated: 2024
