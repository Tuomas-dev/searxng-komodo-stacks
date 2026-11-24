---
name: source-security-review
description: Review project source, configuration, or a code diff for security defects and recommend fixes. Use for defensive code audits, secure code reviews, and remediation planning.
---

# Source security review

Review the source, configuration, and existing tests available in the project or provided in the chat. Use read-only inspection. Do not execute project code, probe services, construct exploit payloads, or provide instructions for reproducing vulnerabilities. Review the repository or paths the user specifies. If the available materials cover only part of the requested scope, identify that coverage limit.

1. Identify the security-sensitive entry points, protected resources, and trust boundaries relevant to the request. Check the implementations of access control, data isolation, input handling, sensitive data handling, and deployment permissions where applicable. For a diff, follow affected call sites and shared controls beyond the changed lines as needed.
2. For each suspected defect, locate the expected security property and trace the relevant source path. Check whether an earlier or later guard, framework guarantee, configuration setting, or existing test refutes the claim. If a deployment fact or other missing evidence determines whether the defect exists, state what information is needed to resolve it.
3. Prioritize actionable findings by plausible impact and the conditions the code supports. Cite repository-relative paths and line numbers where available. Describe the failed security property, affected resource, evidence, and smallest effective fix. Describe a regression test in terms of the behavior the corrected code should enforce.
4. Summarize the reviewed scope, high-priority findings, and open questions. If the review found no actionable defects, say so and identify the coverage limits. Keep sensitive values out of the report.
