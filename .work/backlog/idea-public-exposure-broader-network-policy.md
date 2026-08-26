---
id: idea-public-exposure-broader-network-policy
created: 2026-08-26
updated: 2026-08-26
tags: [security, workflow]
---

# Public-exposure guard: broader network-pattern policy

From the public-flip feature review (2026-08-26, coverage comment — explicitly
NOT a defect): the guard detects the verified operator LAN and tailnet /24
ranges and forbidden paths. Broader classes — all
RFC1918, CGNAT ranges, IPv6-local, MagicDNS names, operator hostnames — are
deliberately uncovered. Expanding coverage is a POLICY decision: broad
regexes flag benign documentation examples (e.g. 192.168.1.1 in router docs),
so it needs an allowlist design (carve-outs for doc contexts / example
ranges) rather than a wider regex alone.

Parked per review adjudication; pick up with the exposure guard next touch.
