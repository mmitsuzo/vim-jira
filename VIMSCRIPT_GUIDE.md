# A beginner's guide to the Vim script in vim-jira

This guide explains the Vim script used in this repository and how its tests
work. It is written for readers who know programming in general (for example
Python, JavaScript or shell) but have never read Vim script.

You don't need to read it in order. If you want to change the code, sections
1–3 are the minimum. If you want to write or fix tests, also read section 5.

- [1. Vim script, legacy script and Vim9 script](#1-vim-script-legacy-script-and-vim9-script)
- [2. How Vim finds and loads a plugin](#2-how-vim-finds-and-loads-a-plugin)
- [3. Vim9 script basics, with examples from this code](#3-vim9-script-basics-with-examples-from-this-code)
- [4. A walk through each file](#4-a-walk-through-each-file)
- [5. The tests](#5-the-tests)
- [6. Debugging tips](#6-debugging-tips)
- [7. Cheat sheet](#7-cheat-sheet)

---

## 1. Vim script, legacy script and Vim9 script

Vim has its own programming language, called **Vim script**. Two dialects
exist:

| | Legacy Vim script | Vim9 script |
|---|---|---|
| Starts with | (nothing) | the line `vim9script` |
| Comments | `" comment` | `# comment` |
| Variables | `let x = 1` | `var x = 1` / `const x = 1` |
| Functions | `function! F() ... endfunction` | `def F() ... enddef` |
| Types | none | optional, checked (`var n: number`) |
| Speed | slow (interpreted line by line) | fast (compiled) |
| Needs | any Vim | Vim 9.0 or later |

This project uses **Vim9 script** everywhere, except two small places that
must also work in old Vim:

- the version guard at the top of `plugin/jira.vim` (old Vim and Neovim
  cannot even parse Vim9 script, so they must stop before reaching it), and
- `syntax/jiraissues.vim` (a syntax file is so simple that legacy script is
  fine; note it uses `let` and `"` comments).

When you search the web for help, many answers are written in legacy script.
They usually still help: the built-in **functions** (`getline()`,
`substitute()`, ...) and **Ex commands** (`:setlocal`, `:split`, ...) are the
same in both dialects. Only the syntax around them differs.

The best reference is Vim's own help. Inside Vim type, for example:

```vim
:help vim9          " Vim9 script overview
:help getline()     " any built-in function
:help :setlocal     " any Ex command
:help pattern       " regular expressions
:help functions     " list of all built-in functions by topic
```

---

## 2. How Vim finds and loads a plugin

### The runtime path

Vim has an option called `'runtimepath'`: a list of directories. Every
plugin directory (this repository, when installed) is added to it. Inside
each directory, Vim looks at sub-directories with fixed names:

| Directory | When Vim reads it | In this repo |
|---|---|---|
| `plugin/` | Every file, once, at startup | `plugin/jira.vim` – defines the `:Jira*` commands |
| `autoload/` | Only when a function from it is first used | `autoload/jira.vim`, `autoload/jira/issue.vim`, `autoload/jira/adf.vim` – all the logic |
| `syntax/` | When a buffer gets that `filetype` | `syntax/jiraissues.vim` – colours for the issue list |
| `doc/` | When the user runs `:help` | `doc/jira.txt` – the help file |

The split between `plugin/` and `autoload/` keeps Vim's startup fast:
`plugin/jira.vim` is tiny (it only defines commands), and the big files are
read the first time the user actually runs a `:Jira...` command.

### What happens when the user types `:JiraIssues`

```
Vim starts
  └─ reads plugin/jira.vim
       ├─ version guard (old Vim / Neovim stop here)
       ├─ "import autoload 'jira.vim'"      → remembered, NOT read yet
       ├─ "import autoload 'jira/issue.vim'" → remembered, NOT read yet
       └─ defines :JiraIssues, :JiraIssue, ...

User types :JiraIssues project = ABC
  └─ runs  issue.Issues('project = ABC')
       └─ first use → Vim now reads autoload/jira/issue.vim
            ├─ which imports autoload/jira.vim and autoload/jira/adf.vim
            └─ Issues() → EnsureCredentials() → Search() → curl → ListLines() → Show()
```

`import autoload 'jira/issue.vim'` means "the file `autoload/jira/issue.vim`
somewhere in the runtime path". After the import, its exported items are
used with the file name as a prefix: `issue.Issues()`, `jira.Option()`,
`adf.ToLines()`.

---

## 3. Vim9 script basics, with examples from this code

### 3.1 Variables and scopes

```vim
var issues: list<any> = []   # can be changed later
const PAGE_SIZE = 100        # cannot be changed
var errors = 0               # type (number) is inferred from the value
```

A prefix in front of a name says *where the variable lives*:

| Prefix | Meaning | Example in this repo |
|---|---|---|
| (none) | Local to the function, or to the script file if declared at top level | `var session_token = ''` in `autoload/jira.vim` |
| `g:` | Global – visible everywhere, set by users in their vimrc | `g:jira_url`, `g:loaded_jira` |
| `b:` | Belongs to the current **buffer** | `b:jira` (the state of a jira buffer) |
| `v:` | Predefined by Vim | `v:version`, `v:exception`, `v:shell_error`, `v:errors` |
| `$` | Environment variable | `$MSYSTEM`, `$JIRA_URL` |
| `&` | A Vim option | `&modified`, `&buftype`, `&runtimepath` |

`get(g:, 'jira_' .. name, default)` (in `jira.Option()`) works because `g:`
itself is a dictionary of all global variables: "give me `g:jira_url`, or
the default if the user did not set it".

Script-level variables (`session_token`, `current_user`) are private to the
file. This is how the typed API token is kept in memory only and is never
visible as a global variable.

### 3.2 Types

| Type | Literal | Notes |
|---|---|---|
| `number` | `42` | integers; also used as boolean (0 = false) |
| `bool` | `true`, `false` | |
| `string` | `'abc'`, `"a\nb"` | see below |
| `list<T>` | `[1, 2, 3]` | like a Python list; index from 0, `l[-1]` is the last |
| `dict<T>` | `{key: 'v'}` | like a Python dict / JSON object |
| `func` | `(x) => x + 1` | function reference / lambda |
| `any` | | any type; used for JSON values whose shape is unknown |
| `null` / `v:null` | | JSON `null` |

`list<any>` means "a list whose items can be anything". `dict<string>`
means "a dict whose values are strings".

In Vim9 script dictionary keys don't need quotes:
`{token: env, source: 'env'}` is the same as `{'token': env, 'source': 'env'}`.

`type(value) == v:t_dict` checks the type at run time. The code does this a
lot when reading JSON from Jira, because a field may be a dict, `null` or
missing:

```vim
# autoload/jira/issue.vim
def Str(value: any): string
  return type(value) == v:t_string ? value : ''
enddef
```

### 3.3 Strings

- **Single quotes** `'...'`: literal. A backslash is just a backslash.
  To write a single quote inside, double it: `'it''s'`.
- **Double quotes** `"..."`: backslash escapes work: `"\n"` is a newline,
  `"\<CR>"` is the Enter key.
- **Concatenation** uses `..` (not `+`): `'jira.vim ' .. VERSION`.
  `s ..= 'x'` appends.

Because regular expressions contain many backslashes, they are almost always
written in single quotes.

### 3.4 Functions

```vim
# autoload/jira.vim
export def Request(method: string, path: string, body: string = ''): dict<any>
  ...
enddef
```

- `def Name(args): returntype` ... `enddef` defines a function.
- `body: string = ''` is an optional argument with a default.
- `export` makes it usable from other files (`jira.Request(...)`). Without
  `export` the function is private to the file.
- Function names must start with a capital letter (or have a prefix like
  `g:`).
- `def g:Test_version()` defines a **global** function. The tests do this so
  that the test runner can find them by name (see section 5).
- `...blocks: list<any>` (in the tests) collects any number of arguments
  into a list, like `*args` in Python.

### 3.5 Lambdas and method calls

```vim
# autoload/jira/issue.vim, ListLines()
const rows = issues->mapnew((_, issue) => {
  ...
  return [...]
})
```

- `(a, b) => expr` is a lambda (an anonymous function). With `{ ... }` it
  can have several statements and a `return`.
- `x->f(y)` is the same as `f(x, y)`. It lets you chain calls:
  `keys(fields)->sort()->filter(...)`.
- `map()`, `mapnew()` and `filter()` call the lambda with **two** arguments:
  the index (or key) and the value. `_` is the name for "argument I don't
  use".
- `map()` changes the list in place; `mapnew()` returns a new list.

### 3.6 Control flow

```vim
if a == 1
elseif a =~ 'x'
else
endif

for item in items
endfor

for [label, value] in [['Type', 'Bug'], ['Status', 'Done']]   # unpacking
endfor

while i < n
  i += 1
endwhile

cond ? 'yes' : 'no'      # ternary
value ?? 'default'       # 'default' if value is null, 0, '' or empty
```

Every block ends with its own keyword (`endif`, `endfor`, `endwhile`,
`endtry`, `enddef`).

### 3.7 Comparing strings and regular expressions

This is the part that surprises newcomers the most.

| Operator | Meaning |
|---|---|
| `==`, `!=` | equal / not equal |
| `==?` | equal, **ignoring case** (`'Done' ==? 'done'` is true) |
| `=~` | **matches the regular expression** on the right |
| `!~` | does not match |
| `=~?` | matches, ignoring case |

```vim
const KEY_PATTERN = '^\a[A-Za-z0-9_]*-\d\+$'
if k !~ KEY_PATTERN
  throw 'jira: invalid issue key: ' .. key
endif
```

Vim's regex syntax differs from Perl/Python regex. In the default ("magic")
mode some characters need a backslash to be special:

| Vim (default) | Perl/Python | Meaning |
|---|---|---|
| `*` | `*` | 0 or more |
| `\+` | `+` | 1 or more |
| `\?` | `?` | 0 or 1 |
| `\(...\)` | `(...)` | group |
| `\%(...\)` | `(?:...)` | group without capture |
| `\|` | `\|` | alternative |
| `\{1,6}` | `{1,6}` | repeat 1 to 6 times |
| `\d` `\s` `\S` | same | digit, white space, non-white |
| `\a` | `[A-Za-z]` | letter |
| `\<` `\>` | `\b` | start / end of a word |
| `\zs` `\ze` | (lookbehind/ahead) | the match **starts / ends here** |
| `\@!` | `(?!...)` | negative lookahead |
| `\c` | `(?i)` | ignore case |
| `\%3l` | – | only on line 3 (used in the syntax file) |

Two "mode switches" appear in the code:

- `\v` ("very magic") at the start makes it work like Perl: `(`, `+`, `{`
  are special without backslash. Used in `jira.ParseOutput()`:
  `'\v^(.*)\n(\d{3})\n*$'`.
- `\V` ("very nomagic") makes everything literal except `\`. Used in the test
  helper `AssertThrows()` to look for plain text.

Useful regex functions:

| Function | Returns |
|---|---|
| `matchstr(s, pat)` | the matched text, or `''` |
| `matchlist(s, pat)` | `[whole, group1, group2, ...]`, or `[]` |
| `matchstrpos(s, pat, start)` | `[text, startpos, endpos]` |
| `substitute(s, pat, repl, flags)` | `s` with the match replaced; flag `'g'` = all |
| `split(s, pat)` | list of pieces; `split(s, '\zs')` splits into characters |

Example from `KeyUnderCursor()`:

```vim
matchstr(getline('.'), '^\a[A-Za-z0-9_]*-\d\+\ze\s')
```

"From the start of the current line, a letter, then letters/digits/`_`, a
`-`, digits – and the match ends (`\ze`) right before a space." So on the
line `ABC-12  To Do  Alice  Fix it` it returns `ABC-12`.

### 3.8 Errors: throw / try / catch

```vim
throw 'jira: Jira URL is not set (g:jira_url or $JIRA_URL)'

try
  ...
catch /^jira:/        # only catch errors whose message starts with "jira:"
  echohl ErrorMsg     # switch to red error colour
  echomsg v:exception # the message that was thrown
  echohl None         # back to normal colour
endtry
```

The project convention: low-level functions **throw** strings starting with
`jira:`, and only the command entry points (`Login()`, `Edit()`,
`Transition()`, ...) **catch** them and show them. Any other error (a real
bug) is not caught by `/^jira:/` and Vim shows it normally.

`catch` without a pattern catches everything (used in `Request()` around
`json_decode()`, and in the test runner).

### 3.9 Ex commands inside functions

Everything you can type after `:` in Vim (an "Ex command") can also be used
in a function:

```vim
setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
setline(1, lines)            # this one is a function
silent :%delete _            # delete all lines; "_" = don't save to a register
execute 'silent keepalt split ' .. fnameescape(name)
normal o                     # press "o" in Normal mode
```

- `execute 'string'` runs a command that is built at run time. It is needed
  when part of the command is in a variable. `fnameescape()` escapes spaces
  and special characters in a file name.
- `silent` hides the command's messages.
- In Vim9 script, a command that starts with a range (like `%` or a line
  number) needs a colon: `:%delete`, `:4`.
- `:normal` runs keys as if typed in Normal mode. The tests use it to
  "press" the plugin's mappings: `normal o`, `execute "normal \<CR>"`.

### 3.10 Buffer, window and option vocabulary

| Word | Meaning |
|---|---|
| **buffer** | Text loaded in memory (usually a file). Has a name and a number. |
| **window** | A view on a buffer. `:split` creates a second window. |
| **tab page** | A set of windows. |
| `buftype=nofile` | The buffer is not a file and is never written. |
| `buftype=acwrite` | `:w` does not write a file; it runs a `BufWriteCmd` autocommand instead. |
| `bufhidden=wipe` | Delete the buffer completely when its window closes. |
| `nobuflisted` | Don't show it in `:ls`. |
| `nomodifiable` | The text cannot be changed. |
| `nomodified` | "There are no unsaved changes." |
| `filetype=...` | Selects highlighting (`syntax/<filetype>.vim`) and settings. |

`setlocal` changes an option only for the current buffer/window; `set` would
change it globally.

### 3.11 Commands, mappings and autocommands

**User commands** (in `plugin/jira.vim`):

```vim
command! -nargs=* JiraIssues issue.Issues(<q-args>)
```

- `command!` defines (or redefines) `:JiraIssues`.
- `-nargs=0` no arguments, `-nargs=1` exactly one, `-nargs=?` zero or one,
  `-nargs=*` any number.
- `<q-args>` is replaced by everything the user typed after the command, as
  one quoted string.
- `-bar` allows `:JiraLogin | echo 'done'`. `:JiraIssues` has no `-bar`,
  so a `|` typed in the JQL is passed to Jira instead of ending the command.

**Mappings** (in `Show()` in `autoload/jira/issue.vim`):

```vim
nnoremap <buffer> <nowait> <silent> r <ScriptCmd>Refresh()<CR>
```

- `nnoremap`: a Normal-mode mapping that is not affected by other mappings.
- `<buffer>`: only in this buffer (so `r` still means "replace" in normal
  files).
- `<nowait>`: run immediately even if other mappings start with `r`.
- `<silent>`: don't echo the command.
- `<ScriptCmd>...<CR>`: run the code **in the context of this script file**,
  which is why it can call the private function `Refresh()`.

**Autocommands** run code on events:

```vim
autocmd BufWriteCmd <buffer> SaveEditor()
```

"When `:w` is used in this buffer, call `SaveEditor()` instead of writing a
file." This is how the edit and comment buffers send their text to Jira.

### 3.12 Useful built-in functions used in this code

| Function | What it does |
|---|---|
| `get(dict, key, default)` | `dict[key]`, or `default` if missing (also works on lists with an index) |
| `has_key(dict, key)` | is the key present? |
| `empty(x)` | true for `''`, `0`, `[]`, `{}`, `null` |
| `len(x)` | length of a string/list/dict |
| `add(list, item)` / `extend(list, list2)` | append one item / many items (in place) |
| `join(list, sep)` / `split(str, pat)` | list ↔ string |
| `trim(s)` | remove white space at both ends |
| `toupper()` / `tolower()` | change case |
| `repeat(s, n)` | `s` repeated `n` times |
| `strdisplaywidth(s)` | how many screen columns `s` uses (a Japanese character uses 2) |
| `getline(n)` / `getline(1, '$')` | one line / all lines of the current buffer |
| `setline(n, lines)` | replace lines starting at line `n` |
| `json_encode()` / `json_decode()` | Vim value ↔ JSON text |
| `system(cmd, input)` | run a shell command, give it `input` on stdin, return its output; exit code in `v:shell_error` |
| `shellescape(s)` | quote `s` for the shell |
| `input(prompt)` / `inputsecret(prompt)` | ask the user for text (secret = not shown) |
| `inputlist(lines)` | show a numbered menu, return the chosen number |
| `has('feature')` | is a feature present? (`has('win32')`, `has('vim9script')`) |
| `exists(':Cmd')` | does a command exist? (2 = yes, exact name) |
| `win_gotoid()`, `bufwinid()`, `winnr('$')` | jump to a window / find a buffer's window / count windows |
| `echo` / `echomsg` | show a message (`echomsg` also stores it in `:messages`) |

---

## 4. A walk through each file

### 4.1 `plugin/jira.vim` – the entry point

```vim
if exists('g:loaded_jira') || !has('vim9script') || v:version < 900
  finish
endif

vim9script
g:loaded_jira = 1
import autoload 'jira.vim'
import autoload 'jira/issue.vim'

command! -nargs=0 -bar JiraVersion jira.Version()
...
```

1. The `if ... finish` part is **legacy** script, so it can be read by any
   Vim. `finish` stops reading the file. It skips the plugin if it was
   already loaded, or if this Vim cannot run Vim9 script (old Vim, Neovim).
2. `vim9script` switches the rest of the file to Vim9 script.
3. `g:loaded_jira = 1` marks the plugin as loaded (a common convention).
4. Two lazy imports, then one line per user command. No logic here.

### 4.2 `autoload/jira.vim` – settings, credentials, HTTP

**Options.** `Option(name, default)` reads `g:jira_<name>` or returns the
default. All user settings go through this one function.

**Platform.** `Platform()` uses only `has(...)` checks to tell Git-Bash,
Cygwin, native Windows and Unix apart, without running any program.

**Credentials.** `Url()`, `User()` and `Token()` look in this order:

- URL and user: `g:jira_url` / `g:jira_user`, else `$JIRA_URL` /
  `$JIRA_USER` (helper `OptionOrEnv()`), and for the user also what was typed
  at `:JiraLogin`.
- Token: the environment variable first (`$JIRA_API_TOKEN`), then the token
  typed at `:JiraLogin` (`session_token`). `Token()` also returns *where* the
  token came from (`source`), which `:JiraCheck` and `:JiraLogin` show.

`getenv(name) ?? ''` – `getenv()` returns `null` for an unset variable;
`?? ''` turns that into an empty string.

**Talking to Jira with curl.** This is the core of the plugin:

```vim
const config = CurlConfig(method, url .. path, user, token, body)
const output = system(shellescape(Curl()) .. ' -K -', join(config, "\n") .. "\n")
```

- `CurlConfig()` builds the lines of a **curl config file**: `url = "..."`,
  `user = "email:token"`, headers, the JSON body, and
  `write-out = "\n%{http_code}"` (makes curl print the HTTP status after the
  body).
- `system('curl -K -', text)` runs curl and passes the config text on
  **stdin** (`-K -` = "read the config from stdin"). Because the token is in
  stdin and not on the command line, other programs on the computer cannot
  see it in the process list, and it is never written to a file.
- `v:shell_error` is curl's exit code. Non-zero means curl itself failed
  (no network, curl not found, ...).
- `ParseOutput()` splits the output into the body and the 3-digit status
  using a regex.
- `json_decode()` turns the body into Vim dicts and lists.

`Request()` returns `{status, body, json}` and lets the caller look at the
status. `Api()` is the convenient version: it returns the JSON, and throws a
`jira: HTTP 404: ...` error for any non-2xx status. `ErrorMessage()` picks a
readable message out of Jira's error JSON.

**Login.** `EnsureCredentials()` asks with `input()` / `inputsecret()` for
anything that is missing. `Authenticate()` calls `GET /rest/api/3/myself` to
check the credentials. `Login()` is the `:JiraLogin` command that uses both
and shows the result.

**Check.** `CheckReport()` builds the `:JiraCheck` report as a list of lines
plus an error count, and `Check()` only prints it. This split is a pattern
used all over the code: **the part that computes is separate from the part
that shows**, so the computing part can be tested.

### 4.3 `autoload/jira/issue.vim` – buffers and issue actions

This is the largest file. Its sections:

**API helpers.**

- `Search(jql)` – Jira returns at most 100 issues per request. The `while`
  loop sends `POST /rest/api/3/search/jql`, adds the page's issues to the
  list, and repeats with the `nextPageToken` Jira returned, until Jira says
  it was the last page or `g:jira_max_results` is reached.
- `Fetch(key)` – `GET /rest/api/3/issue/KEY` with the fields the detail view
  needs.
- `NormalizeKey(key)` – checks the key with `KEY_PATTERN` before it is put
  into a URL (so `ABC-1/../x` cannot reach a different URL) and makes it
  upper case.

**Formatting (pure functions).** These take data and return lines of text.
They don't touch buffers or the network, which makes them easy to test.

- `ListLines(jql, result)` – builds the list buffer text: the JQL line, an
  empty line, the column header (line 3) and one row per issue. It measures
  each column with `strdisplaywidth()` and pads with `Pad()`, so Japanese
  text (2 columns wide per character) still lines up.
- `ColumnAt(header, vcol)` – which column name (`KEY`, `STATUS`, ...) is at
  screen column `vcol` of the header line. Used by the `o` (sort) mapping.
- `SortJql(jql, field)` – replaces the last `ORDER BY ...` of the JQL with
  `ORDER BY field ASC` (or `DESC` if it was already `ASC`). Sorting is done by
  Jira, not in Vim.
- `DetailLines(issue)` – the Markdown-like text of the detail buffer.

**Showing buffers.** `Show(opencmd, name, lines, state)` opens (or reuses)
a buffer named like `jira://issues`, makes it a scratch buffer
(`buftype=nofile`), replaces its text, makes it read-only
(`nomodifiable`), stores the state in `b:jira`, and – only the first time –
adds the single-letter mappings (`r q e c s`, plus `<CR>` and `o` in the
list). Single letters are safe because the buffer cannot be edited.

`ShowList()` and `ShowIssue()` combine "get data → make lines → Show()" and
catch `jira:` errors.

**The edit and comment buffers.** `OpenEditor()` opens a buffer with
`buftype=acwrite` and `autocmd BufWriteCmd <buffer> SaveEditor()`. When the
user types `:w`, Vim calls `SaveEditor()`, which:

1. reads all lines with `getline(1, '$')`;
2. for an edit: splits them into summary and description
   (`ParseEditLines()`), refuses an empty summary, and works out which
   fields really changed (`ChangedFields()`). If nothing changed, nothing is
   sent;
3. unless the user typed `:w!` (`v:cmdbang`), fetches those fields again and
   checks whether someone changed them in Jira meanwhile (`Conflicts()`). On
   a conflict it throws, and the user's text stays in the buffer;
4. sends `PUT /rest/api/3/issue/KEY` (edit) or
   `POST /rest/api/3/issue/KEY/comment` (comment);
5. marks the buffer as saved, closes it and refreshes the list/detail
   windows (`RefreshViews()`).

**Transitions.** `Transition()` gets the allowed status changes
(`GET .../transitions`), lets the user pick one with `inputlist()` or by
name (`FindTransition()`), and posts the choice.

**`ContextKey(arg)`** decides which issue a command works on: the key given
as an argument, else the issue of the current jira buffer (`b:jira.key`),
else the issue on the cursor line of the list.

### 4.4 `autoload/jira/adf.vim` – Jira's document format ↔ text

Jira Cloud stores descriptions and comments as **ADF** (Atlassian Document
Format), a JSON tree like this:

```json
{"type": "doc", "version": 1, "content": [
  {"type": "paragraph", "content": [
    {"type": "text", "text": "Hello "},
    {"type": "text", "text": "world", "marks": [{"type": "strong"}]}
  ]}
]}
```

- `ToLines(doc)` walks the tree **recursively**. `Blocks()` handles a list
  of block nodes (paragraphs, headings, lists, code blocks, ...) and puts an
  empty line between them. `Block()` turns one block into lines; for lists
  it calls `List()`, which again calls `Blocks()` for the items (that is how
  nested lists work). `Inline()` turns text-level nodes (text, mentions,
  emoji, ...) into one string, and `Marks()` adds `` `code` `` and links.
- `FromLines(lines)` does the reverse for the text the user typed.
  `ParseBlocks()` reads lines from top to bottom with an index `i`: a line
  starting with ```` ``` ```` starts a code block, `#` a heading, `-`/`1.` a
  list, `>` a quote, anything else a paragraph. List items and quotes call
  `ParseBlocks()` again on their inner lines. It returns `null` for empty
  text, which the comment code uses to refuse empty comments.

Only a subset of Markdown is understood. This is why the edit code only
sends the description when it changed: converting rich ADF to text and back
would lose formatting.

### 4.5 `syntax/jiraissues.vim` – colours of the list

```vim
syntax match jiraIssuesKey /^\a[A-Za-z0-9_]*-\d\+\ze\s/
highlight default link jiraIssuesKey Identifier
```

`syntax match` gives a name to text matching a regex; `highlight default
link` says "colour it like the standard group `Identifier`", so it follows
the user's colour scheme. `\%3l` in `jiraIssuesColumns` limits the match to
line 3 (the column header). Vim loads this file automatically because
`Show()` sets `filetype=jiraissues`.

---

## 5. The tests

### 5.1 Running them

From the repository root (in Git-Bash, PowerShell or a Unix shell):

```sh
vim -Nu NONE -i NONE -es -S test/run.vim
```

| Flag | Meaning |
|---|---|
| `-N` | not Vi-compatible mode (normal Vim behaviour) |
| `-u NONE` | don't read your vimrc – the tests are not affected by your settings or other plugins |
| `-i NONE` | don't read or write the viminfo file |
| `-es` | silent Ex mode: no screen, no user interaction; good for scripts |
| `-S test/run.vim` | run this script after starting |

The output looks like:

```
PASS Test_adf_blocks
PASS Test_changed_fields
FAIL Test_list_lines
    function Test_list_lines line 2: Expected ['...'] but got ['...']
...
1 test(s) failed.
```

The exit status is 0 only if every test passed, so the command can be used
in CI or a script (`echo $?` in a shell).

### 5.2 How the runner works (`test/run.vim`)

Vim has no test framework of its own, only **assert functions**. The runner
is about 40 lines:

1. Adds the repository to `'runtimepath'` and sources `plugin/jira.vim`, so
   the plugin is loaded just like for a real user.
2. Sources every `test/test_*.vim`. These files only *define* functions
   named `g:Test_...`; nothing runs yet.
3. Finds all functions whose name starts with `Test_`:
   `getcompletion('Test_', 'function')` (the same list you'd get by typing
   `:call Test_<Tab>`). This is why test functions must be **global**
   (`def g:Test_...`).
4. For each test: empties `v:errors`, calls the function, and catches any
   exception as a failure.
5. Vim's `assert_*()` functions **do not stop** the test when they fail –
   they add a message to the list `v:errors`. So after the call, an empty
   `v:errors` means PASS.
6. Prints the result lines with `:%print` (in `-es` mode this goes to the
   terminal) and quits with `qall!` (exit 0) or `cquit!` (exit 1).

### 5.3 Assert functions

| Function | Passes when |
|---|---|
| `assert_equal(expected, actual)` | equal (lists and dicts are compared deeply) |
| `assert_notequal(a, b)` | not equal |
| `assert_true(x)` / `assert_false(x)` | true / false |
| `assert_match(pattern, text)` | `text =~ pattern` |
| `assert_notmatch(pattern, text)` | `text !~ pattern` |
| `assert_report(msg)` | never – always records `msg` as a failure |
| `h.AssertThrows(Func, text)` | calling `Func` throws an error containing `text` (our helper) |

Put the **expected** value first in `assert_equal()`; the failure message
reads "Expected ... but got ...".

Most asserts take an optional last argument, a message shown on failure.
`Test_commands_defined` uses it so you can see *which* command is missing:
`assert_equal(2, exists(':' .. cmd), cmd)`.

### 5.4 A simple test (pure function)

From `test/test_issue.vim`:

```vim
vim9script
import autoload 'jira/issue.vim'
import './helper.vim' as h

def g:Test_normalize_key()
  assert_equal('ABC-1', issue.NormalizeKey(' abc-1 '))
  assert_equal('A1_B-22', issue.NormalizeKey('A1_B-22'))
  for bad in ['', 'ABC', '1ABC-1', 'ABC-1/../x', 'ABC-1?x=1']
    h.AssertThrows(() => issue.NormalizeKey(bad), 'invalid issue key')
  endfor
enddef
```

- The test file imports the module under test the same way the plugin does.
- `import './helper.vim' as h` imports a file by **relative path** and gives
  it the short name `h`.
- `() => issue.NormalizeKey(bad)` is a lambda: it is passed to
  `AssertThrows()` *without being called*, so the helper can call it inside
  its own `try`.

Most tests in the project are like this: give input data, compare the
output of a pure function (`ListLines()`, `SortJql()`, `ParseEditLines()`,
`ChangedFields()`, `Conflicts()`, `adf.ToLines()`, ...) with the expected
value. No network, no buffers.

### 5.5 Why `AssertThrows()` instead of `assert_fails()`

Vim has a built-in `assert_fails()`, but in `-es` mode it makes Vim exit with
status 1 even when the assertion passes, which would make the whole run look
failed. `test/helper.vim` provides a replacement using `try`/`catch`:

```vim
export def AssertThrows(F: func, pattern: string)
  try
    F()
    assert_report('expected exception matching: ' .. pattern)  # no error → fail
  catch
    assert_match('\V' .. escape(pattern, '\'), v:exception)    # literal text match
  endtry
enddef
```

### 5.6 Tests that "talk to Jira": the fake curl

Tests must **never** contact a real Jira site. Instead, `h.SetupFakeCurl()`
writes a small shell script and sets `g:jira_curl` to it. Since the plugin
always runs `g:jira_curl -K -`, it runs the fake instead of curl, and
nothing in the plugin needs to know about tests.

The fake script, for its N-th call:

1. saves what it receives on stdin – the curl config with method, URL and
   JSON body – to `<dir>/config.N` (and `<dir>/config` for the latest);
2. prints `<dir>/body.N` if it exists, else `<dir>/body`, then a newline and
   the content of `<dir>/status`. That is exactly the shape real curl
   produces with `write-out = "\n%{http_code}"`.

Helper functions control and inspect it:

| Helper | Use |
|---|---|
| `dir = h.SetupFakeCurl()` | install the fake and dummy credentials (`https://x.atlassian.net`, `a@example.com`, token `envtoken`) |
| `h.Respond(body, status = 200)` | every following request gets this response; `body` may be a dict (turned into JSON) or a string |
| `h.RespondSequence([b1, b2, ...])` | the next requests get `b1`, `b2`, ... in order (status 200); also resets the request counter |
| `h.LastConfig(dir, n = 0)` | the curl config lines of request `n` (or of the last request) – check the method, URL and body |
| `h.RequestCount(dir)` | how many requests were made since the last `Respond()`/`RespondSequence()` |
| `h.TeardownFakeCurl(dir)` | delete the temporary directory and the credentials |
| `h.HasShell()` | the fake is a `/bin/sh` script, so it only works where a Unix-like shell is available (Linux, macOS, Git-Bash, Cygwin) |

A shortened example from `test/test_update.vim`:

```vim
def g:Test_add_comment()
  if !h.HasShell()
    return                      # native Windows Vim: skip (shows as PASS)
  endif
  const dir = h.SetupFakeCurl()
  only!                         # start with one window ...
  enew!                         # ... and an empty buffer

  h.Respond({isLast: true, issues: [{key: 'ABC-1', fields: {summary: 'x'}}]})
  JiraIssues                    # run the command, like a user would
  :4                            # go to line 4 (the first issue)
  normal c                      # press "c" = comment mapping
  assert_equal('jira://comment/ABC-1', bufname())

  setline(1, ['Looks good', 'thanks'])
  h.RespondSequence(['{"id":"1"}', {isLast: true, issues: []}])
  silent write                  # :w → BufWriteCmd → SaveEditor()
  const post = join(h.LastConfig(dir, 1), "\n")
  assert_match('request = "POST"', post)
  assert_match('url = "https://x.atlassian.net/rest/api/3/issue/ABC-1/comment"', post)
  assert_equal('jira://issues', bufname())   # editor closed, list shown again
  assert_equal(2, h.RequestCount(dir))       # the POST + refreshing the list

  only!
  enew!
  h.TeardownFakeCurl(dir)
enddef
```

The pattern is always the same:

1. **Arrange**: set up the fake and the responses.
2. **Act**: run a command (`JiraIssues`), press mapped keys (`normal c`),
   change text (`setline()`), save (`silent write`).
3. **Assert**: check the buffer (`bufname()`, `getline()`, `&modified`,
   `winnr('$')`) and what was sent (`h.LastConfig()`, `h.RequestCount()`).
4. **Clean up**: `only!`, `enew!`, `h.TeardownFakeCurl(dir)`.

`RespondSequence()` must list responses for **every** request the action
makes, in order. For example saving an edit makes three: the conflict check
(GET), the update (PUT) and the refresh of the detail buffer (GET). If a test
fails unexpectedly, counting the requests is a good first step.

### 5.7 Limits of `-es` mode

- **Messages are not kept**: you cannot check what `echomsg` printed. Check
  the *effect* instead (which buffer is shown, which request was or was not
  sent), or test the pure function that produces the text (for example
  `CheckReport()` instead of `:JiraCheck`).
- **The user cannot answer** `input()`, `inputsecret()` or `inputlist()`,
  and `feedkeys()` does not help. That is why the tests set credentials in
  advance (so the plugin never asks), and why `Test_transition` uses
  `:JiraTransition in progress` (by name) instead of the menu, while the menu
  text itself is tested through `TransitionChoices()`.
- Tests that open buffers should start and end with `only!` and `enew!` so
  that one test's windows don't affect the next.

### 5.8 Writing a new test – step by step

1. Choose the file: `test/test_jira.vim` (core: options, credentials, curl),
   `test/test_issue.vim` (list/detail/ADF to text) or
   `test/test_update.vim` (edit, comment, status, text to ADF).
2. Add a function:

   ```vim
   def g:Test_my_new_thing()
     assert_equal('expected', issue.SomeFunction('input'))
   enddef
   ```

   The name must start with `Test_` and be defined with `g:`.
3. If the function you test is not `export`ed, either test it through an
   exported function that uses it, or (if it is pure and worth testing on
   its own) export it.
4. Restore anything you change: `unlet g:jira_xxx` after setting an option,
   `h.ClearCredentials()` or `h.TeardownFakeCurl(dir)` after credentials.
5. If you added a help tag to `doc/jira.txt`, add it to the list in
   `Test_help_tags`.
6. Run `vim -Nu NONE -i NONE -es -S test/run.vim` and check that it prints
   `All tests passed.`

---

## 6. Debugging tips

Open Vim normally (not `-es`) with only this plugin:

```sh
vim -Nu NONE --cmd "set rtp^=." -c "runtime plugin/jira.vim"
```

Then:

| Command | Use |
|---|---|
| `:messages` | show recent messages, including errors |
| `:echo b:jira` | show the state of the current jira buffer |
| `:JiraCheck` | settings, curl path, login state |
| `:scriptnames` | which script files have been loaded |
| `:verbose nmap <buffer>` | the mappings of this buffer and where they were defined |
| `:verbose set buftype?` | an option's value and who set it |
| `:help E1234` | explanation of an error number |

To quickly try a function, put `echomsg` lines in the code (and remove them
afterwards), or run a single test by hand inside Vim:

```vim
:source test/test_issue.vim
:call Test_sort_jql()
:echo v:errors
```

(Set `v:errors = []` first with `:let v:errors = []` if it is not empty.)

Common Vim9 mistakes:

- Using `+` to join strings – use `..`.
- Forgetting the `:` before a range command (`:%delete`, `:4`).
- Assigning a value of a different type to a typed variable (Vim9 checks
  types and throws `E1012`).
- Writing a regex in double quotes, where `"\d"` is not what you expect –
  use single quotes.
- Calling a private (non-`export`) function from another file.

---

## 7. Cheat sheet

```vim
vim9script                          # first line of a Vim9 file
# comment
var x: number = 1                   # variable
const NAMES = ['a', 'b']            # constant
g:option_name = 'v'                 # global variable
b:state = {kind: 'list'}            # buffer variable
'single' "double\n" 'a' .. 'b'      # strings, concatenation
[1, 2][0]   {k: 1}.k   get(d, 'k', 0)

export def F(a: string, b = 0): list<string>
  return [a]
enddef

if c | ... | elseif d | ... | else | ... | endif
for x in xs | ... | endfor
while c | ... | endwhile
try | ... | catch /^jira:/ | echomsg v:exception | endtry
throw 'jira: message'

xs->mapnew((_, v) => v * 2)         # lambda + method call
s =~ 'regex'   s ==? 'ignorecase'
matchstr(s, pat)   substitute(s, pat, rep, 'g')

import autoload 'jira.vim'          # lazy import, use as jira.Func()
import './helper.vim' as h          # relative import

execute 'split ' .. fnameescape(name)
setlocal buftype=nofile nomodifiable
normal o
nnoremap <buffer> <silent> x <ScriptCmd>Func()<CR>
autocmd BufWriteCmd <buffer> Save()
command! -nargs=* MyCmd Func(<q-args>)

def g:Test_something()              # a test
  assert_equal(expected, actual)
enddef
```
