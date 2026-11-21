# Guide for AI agents (and humans) working on vim-jira

vim-jira (`jira.vim`) is a Vim plugin to work with **Jira Cloud** issues:
list, view, edit summary/description, comment, and change status.
Repository: https://github.com/mmitsuzo/vim-jira

User-facing documentation is `doc/jira.txt` (`:help jira`) and `README.md`.
Read `doc/jira.txt` first to see the current behaviour.

## Requirements

These are decisions made by the project owner. Do not change them without
being asked.

- **Simple and clean** is the most important quality. Prefer small, obvious
  code and few commands, mappings and options. Avoid adding features or
  options that were not requested.
- **Jira Cloud only** (`https://<site>.atlassian.net`, REST API v3). No Jira
  Server / Data Center support.
- **Vim 9.0+ in Vim9 script.** Older Vim and Neovim must skip the plugin
  silently (guard at the top of `plugin/jira.vim`). Tested on Vim 9.2.
- **Git-Bash on Windows must work** (the MSYS2 Vim bundled with Git for
  Windows). Native Windows Vim, Linux and macOS should work too.
- **Minimal external dependencies:** curl is the only one. No Python, Lua,
  Node.js, jq, base64, etc. Everything else is done in Vim script.
- **vim-plug must be supported**, including on-demand loading (`'on'`).
- **Vim help must be provided** and kept up to date (`doc/jira.txt`).

### Credentials

- Account email + API token (HTTP Basic auth, done by curl).
- Settings come from `g:jira_url` / `g:jira_user`, else `$JIRA_URL` /
  `$JIRA_USER`.
- The token comes from the environment variable (`$JIRA_API_TOKEN`, name
  configurable with `g:jira_token_env`) or is typed at `:JiraLogin` with
  `inputsecret()` and kept in memory for the session only.
  **The environment variable always takes precedence over a typed token.**
- The token must never be written to disk or put on a command line. It is
  sent to curl on stdin as a config file (`curl -K -`), see
  `jira.CurlConfig()`.

### Safeguards when updating issues (important to the owner)

- Only fields that actually changed are sent (`issue.ChangedFields()`).
  Editing only the summary must never touch the description, because
  converting the description to text and back loses rich formatting.
- Before saving, the changed fields are fetched again and compared with the
  values Jira returned when the editor was opened, in Jira's raw format
  (`issue.Conflicts()`). On a conflict nothing is saved and the user's text
  is kept; `:w!` overwrites. Changes to fields that are not being saved do
  not block the save.
- Empty summaries and empty comments are refused.

## Layout

| Path | Purpose |
|------|---------|
| `plugin/jira.vim` | Version guard, `:Jira*` commands only. No logic. |
| `autoload/jira.vim` | Options, platform detection, credentials, login, HTTP (`Request()`, `Api()`), `:JiraCheck` |
| `autoload/jira/issue.vim` | Issue list/detail buffers, paging, edit/comment buffers, transitions, conflict check |
| `autoload/jira/adf.vim` | Atlassian Document Format ↔ Markdown-like text (`ToLines()`, `FromLines()`) |
| `syntax/jiraissues.vim` | Highlighting of the issue list buffer |
| `doc/jira.txt` | Vim help |
| `test/run.vim` | Test runner |
| `test/helper.vim` | Shared test helpers (fake curl, `AssertThrows()`, ...) |
| `test/test_*.vim` | Tests |

### Design notes

- Buffers are named `jira://issues`, `jira://issue/KEY`, `jira://edit/KEY`,
  `jira://comment/KEY`; `b:jira` holds their state (`kind`, `key`, `jql`, ...).
- List and detail buffers are read-only scratch buffers (`buftype=nofile`,
  `nobuflisted`). Their single-letter mappings (`<CR> e c s r q`) are safe
  only because the buffers are not modifiable; keep it that way.
- Edit and comment buffers use `buftype=acwrite` with a `BufWriteCmd` that
  calls `SaveEditor()`. The edit buffer is laid out like a git commit
  message: summary on line 1, description from line 3.
- Searches use `POST /rest/api/3/search/jql` and follow `nextPageToken`
  (100 per page) up to `g:jira_max_results` (default 1000, 0 = no limit).
- Other endpoints: `GET /rest/api/3/myself`, `GET|PUT /rest/api/3/issue/KEY`,
  `POST /rest/api/3/issue/KEY/comment`,
  `GET|POST /rest/api/3/issue/KEY/transitions`.
- Issue keys are validated with `issue.NormalizeKey()` before they are put
  in a URL.
- Network calls are synchronous (`system()`), which keeps the code simple.

## Coding conventions

- Vim9 script (`vim9script`) everywhere except the legacy guard at the top
  of `plugin/jira.vim`. 2-space indent, LF line endings (`.editorconfig`,
  `.gitattributes`).
- `plugin/` only defines commands; logic lives in `autoload/` and is
  loaded with `import autoload`.
- Errors are thrown as strings starting with `jira:`, e.g.
  `throw 'jira: invalid issue key: ...'`. Command entry points catch
  `/^jira:/` and show the message with `ErrorMsg` highlighting. Do not let
  raw exceptions reach the user.
- Keep formatting and parsing in **exported pure functions** (e.g.
  `ListLines()`, `DetailLines()`, `ParseEditLines()`, `ChangedFields()`,
  `Conflicts()`) so they can be unit tested without a network.
- Use `strdisplaywidth()` for column alignment; Japanese text must line up.
- User options are read with `jira.Option(name, default)` (`g:jira_{name}`).

## Testing

Run from the repository root (works in Git-Bash, PowerShell and Unix shells):

```sh
vim -Nu NONE -i NONE -es -S test/run.vim
```

Prints `PASS`/`FAIL` per test and exits 0 only if all pass. Always run it
after a change and report the result.

- Tests are `def g:Test_*()` functions in `test/test_*.vim`, using Vim's
  `assert_*()` functions. `test/run.vim` sources every `test_*.vim` file.
- Import helpers with `import './helper.vim' as h`.
- **Never call a real Jira site from tests.** `h.SetupFakeCurl()` installs a
  shell-script fake curl as `g:jira_curl` with dummy credentials.
  `h.Respond(body, status)` sets the response for all requests;
  `h.RespondSequence([...])` sets the responses of the next requests in
  order; `h.LastConfig(dir, n)` returns the curl config of request n
  (method, URL, body); `h.RequestCount(dir)` counts requests. Guard such
  tests with `if !h.HasShell() | return | endif`, and finish with
  `h.TeardownFakeCurl(dir)`.
- Use `h.AssertThrows()` instead of `assert_fails()`: in `-es` mode
  `assert_fails()` makes Vim exit with status 1 even when it passes.
- In `-es` mode messages are not kept in `:messages`, and `inputlist()` /
  `input()` cannot be answered (`feedkeys()` does not work). Test the
  effects (buffers, requests sent) or a pure function instead.
- Tests that open buffers should start and end with `only!` and `enew!`.
- `Test_help_tags` checks that help tags exist; add new tags to its list.

## Checklist for a change

1. Implement it in `autoload/`; add the command to `plugin/jira.vim` if needed.
2. Add or update tests; run the test suite.
3. Update `doc/jira.txt` (contents, commands, options, mappings,
   troubleshooting) and add the new tags to `Test_help_tags`.
4. Update `README.md` if users see the change.
5. If a command was added, add it to the vim-plug `'on'` example in both
   `README.md` and `doc/jira.txt` (`:help jira-install-vim-plug`).
6. Keep this file up to date when requirements or design decisions change.

## Security

- Never commit API tokens, emails of real accounts or site URLs other than
  examples (`example.atlassian.net`, `you@example.com`).
- Keep personal setup scripts with credentials outside the repository.
- Check `git status` for unexpected files before committing.
