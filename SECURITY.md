# Security policy

Please do not report a vulnerability in a public issue, pull request, or
playground example. Send a private report to the maintainer listed in the
repository profile, or use GitHub's **Report a vulnerability** button when
private vulnerability reporting is enabled. Include a minimal reproduction,
affected version or revision, impact, and a safe contact method.

Ibex's generated parsers execute Ruby semantic actions and are not sandboxes.
The browser playground intentionally does not execute actions or upload source;
reports about either boundary should state which path was used.

Maintainers will acknowledge a report, reproduce it in an isolated environment,
coordinate a fix or mitigation, and publish release guidance after a fix is
available. Please allow reasonable time for coordination before public
disclosure.
