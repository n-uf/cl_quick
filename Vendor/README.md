# Vendored: cl_audit's shared modules

`cl_audit-6bce89f/` is n-uf/cl_audit's `Core/`, `Run/` and `Auth/` at commit **6bce89f** (release 26.11.53), exactly as
they are there (`git archive 6bce89f Core Auth Run`), with that commit's own checks of them (`Checks/core`, `Checks/runs`,
`Checks/auth`).

| Folder | Module | Layer |
| --- | --- | --- |
| `Core/` | ProfileCore | Foundation only; imports nothing of ours |
| `Run/` | Runs | Foundation only; the one runner, the cleaned environment |
| `Auth/` | ClaudeAuth | imports ProfileCore and Runs: one folder's Claude Code sign-in |

## The rule

**Never edit these files here.** A change goes upstream, into cl_audit, and comes back as a new vendored commit (a new
`cl_audit-<sha>/` folder and this README pointed at it).
