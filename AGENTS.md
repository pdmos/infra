# Agent Guide

This repository defines production infrastructure. Assume the user may be non-technical: explain risks and outcomes plainly, perform requested work end to end, and never rely on the user to infer an operational step.

Keep changes small, match existing patterns, and preserve unrelated worktree changes.

## Repository map

- Each `hosts/<hostname>/` directory defines one NixOS host. Start at its `configuration.nix`.
- `flake.nix` exposes deployable hosts as `nixosConfigurations.<hostname>`.
- `tofu/` provisions infrastructure and exposes host addresses through `tofu/outputs.tf`.
- `nix develop` opens the operational shell and loads the credentials required by Nix and OpenTofu.

## Managing secrets

- Agenix rules and recipients are defined in `secrets/secrets.nix`. Public keys come from `ssh-keys.nix`.
- To create a secret, add its `<name>.age` rule and intended recipients first, then run `cd secrets && agenix -e <name>.age` from `nix develop`.
- To edit an existing secret, run the same `agenix -e <name>.age` command. To apply recipient changes, run `cd secrets && agenix -r`.
- `agenix -e` opens `$EDITOR` interactively. If the agent cannot operate the editor, ask the user to complete this step. Never pass secret values through command arguments or tool output.
- Never read a secret into command output, logs, chat, or Git. Commit only the encrypted `.age` file and its rule.
- OpenTofu environment variables are also stored as Agenix secrets and loaded by `nix develop`.

## Changing configuration

- Inspect the target host and its imported modules before editing.
- Validate NixOS options against <https://github.com/NixOS/nixpkgs> and <https://search.nixos.org>. Never guess option names or types.
- Follow the <https://nixos.org/manual/nixpkgs/stable/> when adding a package derivation.

## Deploying a host

Deploy only after the user explicitly approves the target host and the current changes.

The SSH key may require YubiKey touch and a PIN or password. Agents must not request, handle, or expose these secrets. If authentication is interactive or uncertain, prepare and validate the deployment, then give the user the exact command to run. The user may share non-secret output for diagnosis.

1. Enter `nix develop` if not in one already.
2. Identify the host in `hosts/` and its matching address output in `tofu/outputs.tf`.
3. Read the address with `tofu -chdir=tofu output -raw <output-name>`.
4. Run `nix flake check` immediately before deployment.
5. Do not deploy when checks fail. Diagnose or report the exact blocker.
6. Deploy with `nixos-rebuild switch --flake .#<hostname> --target-host root@<ipv4> --build-host root@<ipv4>`.
7. Confirm the command succeeded, then verify the affected services and user-visible behavior. A successful rebuild alone is not sufficient verification.

Never run an OpenTofu apply, destroy resources, rotate secrets, or change remote state without separate explicit approval.

## Changing infrastructure

OpenTofu manages the Hetzner server, public IPs and SSH key, plus Cloudflare DNS and access rules. Its local state and any saved plans are encrypted with the passphrase loaded by `nix develop`.

1. Enter `nix develop`, then run `tofu -chdir=tofu fmt` and `tofu -chdir=tofu validate`.
2. Run `tofu -chdir=tofu plan` and inspect its output. A saved plan may be used when the reviewed plan must be applied exactly.
3. Explain every planned create, update, replacement, and deletion in plain language. Treat replacements and deletions as destructive.
4. Obtain explicit approval before running `tofu -chdir=tofu apply`. If its plan differs from the reviewed plan, stop and obtain approval again.
5. Verify the changed resources and dependent services.

Never use `-auto-approve`, manually edit state, or apply while another infrastructure operation is running.

## Diagnosing deployments

- Start with the read-only account: `ssh debug@<ipv4>`.
- Use it to inspect service status, failed units, system logs, ports, and local health endpoints. It can read the journal but has no `sudo` or administrative access.
- Check the specific changed service and `systemctl --failed`; use `journalctl` with a unit and bounded time range where possible.
- Do not modify the host through the debug account. Configuration fixes belong in this repository and must follow the normal validation and deployment flow.
- If diagnosis or recovery requires elevated access, explain why and ask the user for a higher-permission account or explicit approval.
- After a failed deployment, preserve the failing command and relevant output. Diagnose before retrying; do not repeatedly deploy the same configuration.

## Rolling back a host

Rollback restores the target host's previous NixOS system generation. It does not revert Git, data, secrets, or OpenTofu resources.

1. Confirm the failure was caused by the latest NixOS deployment and that the previous generation is expected to be safe.
2. Explain the impact and obtain explicit approval to roll back the target host.
3. Run `nixos-rebuild switch --rollback --target-host root@<ipv4>`. Do not pass `--flake`; rollback selects the previous generation from the target's system profile.
4. Verify connectivity, `systemctl --failed`, affected services, logs, and user-visible behavior.
5. Keep the configuration change unapplied, diagnose the cause in this repository, and use the normal deployment flow for the fix.

If SSH authentication needs YubiKey interaction, PIN, or a password, give the user the exact rollback command to run instead of attempting it.

## Git and pull requests

- Use a dedicated branch and one conventional commit per logical change, for example `feat(lena): add debug account`.
- Commit messages state the outcome, not the implementation process.
- Keep pull request descriptions concise: state what changed and how it was verified.
- Do not commit, amend, push, or open a pull request unless asked.
- Before committing, format the Nix files with `nix fmt`.

## Documentation and Comments

- Don't edit CLAUDE.md, it is a symlink to AGENTS.md. If needed, edit AGENTS.md instead.
- Add comments only for non-obvious intent.
- Comments should always be in English.
