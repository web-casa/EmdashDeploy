# Compatibility Policy

This project now uses a single-entry command style:

- `bootstrap.sh --lang=<code>`
- `install.sh --lang=<code>`
- `emdashctl --lang=<code>`

## Primary Interface

These are the only forms documented as the preferred interface for new users and new automation.

Examples:

```bash
curl -fsSL https://raw.githubusercontent.com/web-casa/EmdashDeploy/main/bootstrap.sh | sudo bash -s -- --lang=zh-CN
sudo bash install.sh --lang=ja --activate
emdashctl --lang=de status
```

## Legacy Compatibility Aliases

The following legacy entrypoints are still kept for compatibility:

- `bootstrap.<lang>.sh`
- `install-emdash.<lang>.sh`
- `emdashctl.<lang>.sh`

They are preserved for these reasons:

- existing raw GitHub URLs may still reference them
- bookmarked operator commands may still use them
- existing cron jobs, runbooks, or local scripts may still call them

In the repository, these aliases are lightweight symlinks that point to the unified entrypoints.

On installed systems, `emdashctl.<lang>.sh` aliases are still created so existing automation does not break after upgrade or reinstall.

## Removal Policy

Legacy aliases are compatibility-only, not primary interface.

They should not be removed in a patch release or a compatibility hardening release.

If removal is ever needed, it should happen only after all of the following:

1. the unified `--lang` interface has been the only documented default for at least one full release cycle
2. release notes explicitly mark the aliases as deprecated
3. the next release notes explicitly announce the removal window
4. removal happens no earlier than a later compatibility-breaking release line

## Repository Cleanliness Rule

To keep the repository clean while preserving compatibility:

- documentation should show only the unified entrypoints
- legacy aliases should stay tiny and maintenance-free
- no new language-specific wrapper logic should be added
- all real behavior should remain in `bootstrap.sh`, `install.sh`, `install-emdash.sh`, and `emdashctl`
