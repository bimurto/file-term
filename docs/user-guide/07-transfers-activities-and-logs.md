# 7 Transfers, activities and logs

## Activities

View › Show/Hide Activities opens a panel below the panes. It lists every queued, running and finished job from all windows: copies, moves, deletes, renames, archive jobs, tools, Git commands and uploads.

A running job shows its source and destination, progress, bytes, speed and estimated time left. A finished job shows how many items succeeded, were skipped and failed. Each row has buttons for what's possible at that moment.

Jobs aren't kept after you quit.

## Logs

View › Show/Hide Logs opens the operation log beside Activities. Tool commands and Git output, with exit codes, appear here too.

- **Copy All** copies the whole log.
- **Export…** saves it as a text file.

### What logs leave out

FileTerm removes common credential shapes from every log line before storing it. Removed values appear as `•••`. It catches:

- Passwords and tokens in URLs, such as `https://user:token@host`.
- Authorization headers and `curl -u user:password`.
- Options and variables with names such as `--password`, `API_TOKEN=` or `?token=`.
- Tokens recognizable on their own, such as GitHub, Slack and AWS key IDs.

This matches patterns, so it can't promise to catch every secret. A tool's command or Git's output could contain anything. Read a log before sharing it.

### Hide Personal Paths

Turn on Hide Personal Paths at the top of the Logs panel before you copy or export. It replaces home folders such as `/Users/yourname` with `~`, so the log doesn't show your user name.

- It applies only to Copy All and Export…. The panel itself still shows full paths.
- It isn't saved as a setting, so check it each time you share a log.

FileTerm has no crash reporter and writes no log file. Logs stay in memory until you copy or export them, and they're gone when you quit.

## Replace policy

Settings › Transfers › Conflicts sets what happens when a file or folder already exists.

- **Existing files:** Ask, Replace, Replace Older, Keep Both, Skip or Stop.
- **Existing folders:** Ask, Merge, Replace, Keep Both, Skip or Stop.

The default for both is Ask. See [chapter 4](04-creating-copying-and-moving.md#conflicts) for what each choice does.

## Resume and merge policies

Merge is covered by the Existing folders policy above.

Pause and Resume work within a session. The transfer continues from where it stopped.

Resuming a partial file after restarting FileTerm or after an interruption **isn't built**. The Resume policy control in Settings is grayed out and marked as a future capability. Copies across locations write to a hidden `.part` file first. Cancel and failure remove it, but a crash can leave one behind.

## Upload and download limits

Settings › Transfers › Bandwidth has separate upload and download limits, in bytes per second. Each is off by default. A limit is shared across all jobs running in that direction.

Copies between local folders aren't limited. A copy between two servers counts against both limits.

## Retry failures

- **Retry** appears on a failed job. It's grayed out once part of the job has already taken effect, to avoid repeating copies or moves.
- Tools and Git commands are never retried, because rerunning them may not be safe.
- Retrying only the unfinished items of a partly finished job isn't built.

Settings › Transfers › Reliability can retry temporary failures automatically. This is off by default, with a limit of 5 retries you can change.

## Simultaneous transfers

Settings › Transfers › Reliability › Concurrent operations sets how many jobs run at once. The default is 5, and the range is 1 to 64. Copies to the same server run one at a time, and copies to different servers run together.

## Queue ordering

Each queued job has Move earlier and Move later buttons. Queued and running jobs have Pause, paused jobs have Resume, and unfinished jobs have Cancel.

## Completion check

Settings › Transfers › Verify copies checks each copy after writing it:

- **None:** the default.
- **File size:** compares sizes.
- **Checksum:** compares file contents using SHA-256, which is slower.

## Failure diagnosis

When a job fails:

1. Read the error in the job's row in Activities. Some failures also show a hint.
2. Open Logs for the full detail of that job.
3. If a local folder can't be opened, the pane offers Open System Settings for the missing permission. A denied copy or move reports its error in Activities and Logs, without that button.
4. If a server refuses access, check the account and folder with its administrator.

FileTerm won't quit while jobs are active. Wait for them, or cancel them in Activities.
