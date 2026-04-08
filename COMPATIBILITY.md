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

## Repository Interface Cleanup

The repository no longer ships language-specific alias files such as:

- `bootstrap.<lang>.sh`
- `install-emdash.<lang>.sh`
- `emdashctl.<lang>.sh`

The supported interface is now only:

- `bootstrap.sh --lang=<code>`
- `install.sh --lang=<code>`
- `emdashctl --lang=<code>`

This keeps the repository root small and avoids publishing multiple language-specific entrypoints that all do the same thing.

## Compatibility Boundary

The project no longer guarantees compatibility for old repository paths or raw GitHub URLs such as:

- `.../bootstrap.zh-TW.sh`
- `.../install-emdash.zh-CN.sh`
- `.../emdashctl.ko.sh`

Those old entrypoints are considered removed.

## Installed-System Migration

To reduce upgrade breakage, install and upgrade runs now perform a migration step:

- recognized command invocations in system-level cron entries are rewritten to `emdashctl --lang=<code>`
- recognized `Exec*=` lines in `/etc/systemd/system/*.service` and `*.timer` are rewritten to `emdashctl --lang=<code>`
- stale `/usr/local/bin/emdashctl.<lang>.sh` aliases are removed

This preserves the important runtime compatibility path without keeping extra wrapper files in the repository or on the target host.

It does not rewrite arbitrary user scripts, user crontabs, bookmarked shell history, or old raw GitHub URLs.

## Removal Policy

Language-specific alias files are removed from the repository and are not recreated on target systems.

The migration layer exists only to help installed automation converge to the unified command style.

## Repository Cleanliness Rule

To keep the repository clean:

- documentation should show only the unified entrypoints
- no language-specific alias files should be reintroduced
- no new language-specific wrapper logic should be added
- all real behavior should remain in `bootstrap.sh`, `install.sh`, `install-emdash.sh`, and `emdashctl`
