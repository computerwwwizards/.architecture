---
status: "live"
---

# Prohibit Local Development Environments for Third-Party Code

## Context and Problem Statement
Third-party code and open-source dependencies are inherently insecure. Current community policies and security checks are insufficient to prevent malware intentionally hidden by the original author, let alone complex supply-chain attacks. Furthermore, accidental complexity frequently introduces unpatched vulnerabilities into the dependency tree. While local development tools are currently hardened and secured behind enforced VPNs, these local measures cannot guarantee immunity against bugs that lead to privilege escalation on the developer's physical machine. We must decide whether to continue allowing local execution of third-party dependencies under hardened conditions or to strictly prohibit local development to eliminate endpoint exposure, shifting execution to cloud environments accessed via client browsers.

## Decision Drivers
* Strict containment of execution payloads to prevent host-level privilege escalation.
* Total isolation of physical developer endpoints from intentional author-injected malware and accidental runtime vulnerabilities.
* Elimination of the local hardware blast radius (e.g., SSH keys, hardware tokens, local file systems) from unverified third-party dependencies.
* Leveraging existing mature client-side sandboxes (web browsers) as an explicit security boundary.

## Considered Options
* Permit Local Development with Hardening and VPNs
* Prohibit Local Development Environments (Mandate Cloud/Remote Workspaces)

## Decision Outcome
Chosen option: "Prohibit Local Development Environments (Mandate Cloud/Remote Workspaces)", because the fundamental exposure of local physical endpoints to untrusted third-party code execution cannot be safely mitigated through local hardening or VPN tunnels. Shifting execution to the cloud explicitly leverages the web browser's out-of-the-box process isolation and HTTP header policies as a secondary, hardened security boundary, ensuring that even if a cloud environment is compromised, the local OS remains protected.

### Benefits
* Good, because client-side access is brokered through a web browser, utilizing native process isolation, JIT hardening, and strict HTTP header policies (like Content Security Policy and Cross-Origin Embedder Policies) to protect the underlying host OS from remote malicious outputs.

### Trade-offs
* Bad, because local offline workflows are permanently disabled, introducing a strict dependency on continuous network connectivity for step-through debugging and REPL execution.

### Confirmation
Endpoint management systems (MDM) and local binary execution controls will explicitly block the execution of unapproved compilers, package managers, and container daemons on local host operating systems, restricting access to approved web-based thin clients.

## Pros and Cons of the Options

### Permit Local Development with Hardening and VPNs
Executing code, build tools, and third-party dependencies directly on the developer's local machine, utilizing enforced VPNs and local runtime hardening policies to restrict network and system access.

* Good, because local execution bypasses network transit overhead, resulting in zero-latency memory allocation and file system reads during compilation.
* Neutral, because VPN tunneling ensures all external network traffic from the local machine is encrypted, though it provides zero inspection or isolation for local runtime process execution.
* Bad, because hardened local tooling cannot prevent zero-day memory corruption or logic bugs in third-party dependencies from triggering privilege escalation directly on the host operating system.
* Bad, because malware intentionally obfuscated by an open-source author can access local developer credentials and environment variables if a local sandbox escape occurs.

### Prohibit Local Development Environments (Mandate Cloud/Remote Workspaces)
Enforcing a strict prohibition on local execution, requiring all third-party code compilation, dependency resolution, and execution to occur in isolated, managed cloud environments accessed primarily via browser-based thin clients.

* Good, because any executed malware or accidental vulnerability detonates within an ephemeral, network-isolated cloud boundary, completely severing the direct privilege escalation path to the physical endpoint.
* Good, because accessing the remote environment via a web browser introduces an additional hardened security layer on top of the OS, utilizing built-in browser sandboxing and hard policies via HTTP headers to contain potentially malicious remote payloads.
* Neutral, because although AST transformations and heavy compilation happen across a network boundary, local state synchronization with remote Language Server Protocols (LSPs) significantly minimizes the perceived latency of IDE interactions and keystrokes.
* Bad, because a permanent requirement for network connectivity eliminates the ability to resolve dependencies, compile code, or execute tests in offline or heavily degraded network conditions.
