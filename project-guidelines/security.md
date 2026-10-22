# Security Guidelines for this Project and Repo overall

## Do not expose any critical infrastructure
* Always remember this repo IS PUBLIC. Treat it as such, and do not get lax with security. Always safeguard your critical information.
* AI Agents and users should stray from any commands, actions, text and or notes that can expose ANY secrets, keys, api, PII(Personal Identifiable Information), etc, to the console, terminal, agent-chat, or public view in general.

## Always verify the authenticity and fortification of your code
* AI Agents and users should ALWAYS verify the security structure and effeciency of the code they put into this repo and project. This includes but is not limited to:
    - Packages and Dependencies, AI Agents and users should always check for any security vulnerabilities or possible areas of exploitation
    - Webhooks and API Keys, only the necessary permissions should ever be granted through these to minimize attack surfaces
    - Code should always be up to OWASP and OSINT security standards

## Always update the ".gitignore" to house the critical components of this project
* AI Agents and users should ALWAYS keep the ".gitignore" up-to-date during the course of their time working in this repo. Any backend systems or database sets(especially keys or ".envs") should IMMEDIATELY be added to the ".gitignore" to avoid leaking any high-risk components to the public
* When making builds and applications, keep only one ".gitignore"(the one under the root directory) and CONSISTENTLY update the "/.gitignore" under the root directory. Always include critical infrastructure to builds, packages, and other applicable pieces within the ".gitignore" to prevent any critical leakage.