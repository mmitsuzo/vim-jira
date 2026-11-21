# vim-jira

Work with Jira Cloud issues from Vim (`jira.vim`, see `:help jira`).

> Status: early development.

## Requirements

- Vim 9.0+ (Vim9 script). Older Vim and Neovim skip the plugin silently.
- `curl` — the only external dependency. It ships with Git for Windows
  (Git-Bash), Windows 10+, macOS and most Linux distributions.

Run `:JiraCheck` to verify your environment.

## Installation

### vim-plug

With [vim-plug](https://github.com/junegunn/vim-plug):

```vim
call plug#begin()
Plug 'mmitsuzo/vim-jira'
call plug#end()
```

Then `:PlugInstall`. vim-plug generates the help tags automatically.
On-demand loading also works:

```vim
Plug 'mmitsuzo/vim-jira', { 'on': ['JiraIssues', 'JiraIssue',
      \ 'JiraEdit', 'JiraComment', 'JiraTransition',
      \ 'JiraLogin', 'JiraLogout', 'JiraCheck', 'JiraVersion'] }
```

### Vim packages

```sh
git clone https://github.com/mmitsuzo/vim-jira.git ~/.vim/pack/plugins/start/vim-jira
```

For native Windows Vim/gVim use `~/vimfiles/pack/plugins/start/vim-jira`.
Then generate help tags: `:helptags ALL`.

### Git-Bash on Windows

The Vim bundled with Git for Windows is supported. It is an MSYS2 (Unix-like)
build, so it uses `~/.vim` and `~/.vimrc` — **not** `~/vimfiles` / `~/_vimrc`.
Install vim-plug for it with:

```sh
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
```

## Login (Jira Cloud)

Only Jira Cloud (`https://<site>.atlassian.net`) is supported. Create an
[API token](https://id.atlassian.com/manage-profile/security/api-tokens), then
either set it in the environment (recommended; it always takes precedence):

```sh
export JIRA_URL=https://example.atlassian.net
export JIRA_USER=you@example.com
export JIRA_API_TOKEN=xxxxxxxx
```

or leave `JIRA_API_TOKEN` unset and type it when `:JiraLogin` asks. A typed
token is kept in memory for the current Vim session only. `:JiraLogout`
forgets it. URL and email can also be set with `g:jira_url` / `g:jira_user`.

| Command | Purpose |
|---------|---------|
| `:JiraLogin` | Ask for missing settings and verify them |
| `:JiraLogout` | Forget the typed token |
| `:JiraCheck` | Show environment, settings and login state |

## Issues

```vim
:JiraIssues                          " your unresolved issues
:JiraIssues project = ABC ORDER BY created DESC
:JiraIssue ABC-12                    " details of one issue
```

The list shows key, status, assignee and summary under a column header. All
matching issues are loaded page by page (up to `g:jira_max_results`, default
1000; `0` = no limit). Press `<CR>` on an issue to open its details (fields,
description, comments) in a split. Press `o` to sort by the column under the
cursor (again to reverse); Jira does the sorting via the JQL `ORDER BY`.

| Key | Command | Action |
|-----|---------|--------|
| `o` | | Sort the list by the column under the cursor |
| `e` | `:JiraEdit [key]` | Edit summary (line 1) and description (from line 3); `:w` saves |
| `c` | `:JiraComment [key]` | Write a comment; `:w` posts |
| `s` | `:JiraTransition [key] [status]` | Change status (menu, or e.g. `:JiraTransition Done`) |
| `r` | | Reload |
| `q` | | Close |

Only changed fields are saved. If someone else changed the same field in
Jira while you were editing, the save is refused and your text is kept
(`:w!` overwrites anyway). Descriptions are edited as plain text, so
saving a *changed* description simplifies rich formatting (tables, mentions,
bold, ...); see `:help jira-edit`.

## Documentation

See `:help jira`.

## Development

See [AGENTS.md](AGENTS.md) for requirements, design decisions, conventions
and the testing guide (also used by AI coding agents; `CLAUDE.md` points
there).

Layout:

| Path | Purpose |
|------|---------|
| `plugin/jira.vim` | Load guard, commands, mappings |
| `autoload/jira.vim` | Settings, credentials, HTTP via curl (lazy-loaded) |
| `autoload/jira/issue.vim` | Issue list, detail and edit buffers; updates |
| `autoload/jira/adf.vim` | Atlassian Document Format ↔ text |
| `syntax/jiraissues.vim` | Highlighting for the issue list |
| `doc/jira.txt` | Vim help file |
| `test/` | Tests using Vim's built-in `assert_*()` |

Try the plugin from a working copy without installing it:

```sh
vim --cmd "set rtp^=."
```

Run the tests (works in Git-Bash too):

```sh
vim -Nu NONE -i NONE -es -S test/run.vim
```
