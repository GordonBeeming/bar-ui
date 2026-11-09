# A Bar App's data is keyed by Account, and the file name tells readers which one

ClaudeBar can now watch more than one Claude sign-in, so a Bar App is no longer one series of Limits and tokens. Identity in the Archive and in the UI becomes the Bar App plus an Account. Tracking settings, the Telemetry Folder and import folders stay per Bar App, because each Bar App has one of each.

Existing Archive rows become the `default` Account. The Archive is permanent and can't be rebuilt from files ([ADR 0002](0002-dashboard-archive-is-permanent-store.md)), so the schema change runs in place, in one transaction, and a second run changes nothing.

An Account other than `default` writes its own files, `<service>.<account id>-metrics-YYYY-MM-DD.jsonl`, and puts `account.id` in the resource. We kept `bar.spec.version` at `"1"`. A Bar UI build from before this only imports names shaped `<service>-(metrics|logs)-<date>.jsonl`, so it skips the new files instead of misreading them. Bumping the version would have made those builds report every record as non-conforming. The file name and `account.id` must agree; a record that disagrees is counted as skipped.

We considered one file per Bar App with the Account only in the resource. Older readers would then have merged two Accounts into one series without noticing. Separate files also let each Account's retention delete whole files, as the spec already requires.

## Opening an upgraded Archive with an older build

An older Bar UI or helper may open the Archive after it has been upgraded, because the helper keeps running until it is replaced. The upgrade therefore leaves the old table names alone and writes its tables under new names (a `_v2` suffix, with new index names too). The old tables are dropped at the end of the upgrade.

An older build then finds none of its tables, creates its own empty ones, sets `user_version` back to 1 and imports into them. It never reads or writes the new tables, so it can't mix Accounts or fail on a key that changed.

Nothing an older build imported is lost. Every open of the new build looks at which tables exist, not at `user_version`, which an older build overwrites. If it finds old-named tables, it adds their rows to the new tables as the `default` Account in one transaction, then drops them. Rows both sets hold are kept once. The new build's read positions win over the older build's.

An older build that is already running when the upgrade happens has its tables dropped under it, so its queries fail until it is restarted. Replace the app and its helper together.
