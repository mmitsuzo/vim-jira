vim9script
# Issue list (:JiraIssues) and issue detail (:JiraIssue) buffers.

import autoload 'jira.vim'
import autoload 'jira/adf.vim'

const LIST_BUFFER = 'jira://issues'
const LIST_FIELDS = ['summary', 'status', 'assignee']
# Column headers of the list; lowercased they are the JQL fields to sort by.
const LIST_COLUMNS = ['KEY', 'STATUS', 'ASSIGNEE', 'SUMMARY']
const MORE_NOTE = '-- more issues exist: narrow the JQL or raise g:jira_max_results --'
const DETAIL_FIELDS = ['summary', 'status', 'issuetype', 'priority', 'assignee',
  'reporter', 'created', 'updated', 'labels', 'description', 'comment']
const KEY_PATTERN = '^\a[A-Za-z0-9_]*-\d\+$'

export def DefaultJql(): string
  return jira.Option('default_jql',
    'assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC')
enddef

# ----------------------------------------------------------------------------
# API

const PAGE_SIZE = 100

# Searches with JQL, following nextPageToken until all issues are loaded
# or g:jira_max_results (0 = no limit) is reached.
# Returns {issues, isLast}; isLast is false when the limit cut the result.
export def Search(jql: string): dict<any>
  const limit = jira.Option('max_results', 1000)
  var issues: list<any> = []
  var token = ''
  while true
    var request: dict<any> = {
      jql: jql,
      fields: LIST_FIELDS,
      maxResults: limit > 0 ? min([PAGE_SIZE, limit - len(issues)]) : PAGE_SIZE,
    }
    if !empty(token)
      request.nextPageToken = token
    endif
    const page = jira.Api('POST', '/rest/api/3/search/jql', json_encode(request))
    extend(issues, get(page, 'issues', []))
    token = Str(get(page, 'nextPageToken', ''))
    if get(page, 'isLast', empty(token)) || empty(token)
      return {issues: issues, isLast: true}
    elseif limit > 0 && len(issues) >= limit
      return {issues: issues[: limit - 1], isLast: false}
    endif
    redraw
    echo 'jira: loaded ' .. len(issues) .. ' issues...'
  endwhile
  return {}
enddef

export def Fetch(key: string): dict<any>
  return jira.Api('GET', '/rest/api/3/issue/' .. key
    .. '?fields=' .. join(DETAIL_FIELDS, ','))
enddef

# Validates and normalizes an issue key ("abc-1" -> "ABC-1").
export def NormalizeKey(key: string): string
  const k = trim(key)
  if k !~ KEY_PATTERN
    throw 'jira: invalid issue key: ' .. key
  endif
  return toupper(k)
enddef

# ----------------------------------------------------------------------------
# Formatting (pure functions, unit tested)

# String value of a field; '' for null/missing.
def Str(value: any): string
  return type(value) == v:t_string ? value : ''
enddef

# Display name of a user, status, priority, ... object.
def Name(obj: any): string
  if type(obj) != v:t_dict
    return ''
  endif
  return Str(get(obj, 'displayName', get(obj, 'name', '')))
enddef

# "2026-11-01T10:20:30.000+0900" -> "2026-11-01 10:20"
def Date(value: any): string
  return substitute(Str(value)[: 15], 'T', ' ', '')
enddef

# Truncates to at most width display cells.
def Truncate(s: string, width: number): string
  if strdisplaywidth(s) <= width
    return s
  endif
  var r = ''
  for c in split(s, '\zs')
    if strdisplaywidth(r .. c .. '~') > width
      break
    endif
    r ..= c
  endfor
  return r .. '~'
enddef

# Pads with spaces to width display cells (works for CJK text).
def Pad(s: string, width: number): string
  return s .. repeat(' ', width - strdisplaywidth(s))
enddef

export def ListLines(jql: string, result: dict<any>): list<string>
  const issues = get(result, 'issues', [])
  const rows = issues->mapnew((_, issue) => {
    const f = get(issue, 'fields', {})
    const assignee = Truncate(Name(get(f, 'assignee', {})), 20)
    return [
      Str(get(issue, 'key', '')),
      Truncate(Name(get(f, 'status', {})), 20),
      empty(assignee) ? '-' : assignee,
      Str(get(f, 'summary', '')),
    ]
  })
  if empty(rows)
    return ['JQL: ' .. jql, '', '(no issues)']
      + (get(result, 'isLast', true) ? [] : ['', MORE_NOTE])
  endif

  # The column header is line 3 (see ColumnAt()).
  const table = [LIST_COLUMNS] + rows
  var widths = [0, 0, 0]
  for row in table
    for i in range(3)
      widths[i] = max([widths[i], strdisplaywidth(row[i])])
    endfor
  endfor
  var lines = ['JQL: ' .. jql, '']
  for row in table
    add(lines, trim(Pad(row[0], widths[0]) .. '  ' .. Pad(row[1], widths[1])
      .. '  ' .. Pad(row[2], widths[2]) .. '  ' .. row[3], ' ', 2))
  endfor
  if !get(result, 'isLast', true)
    extend(lines, ['', MORE_NOTE])
  endif
  return lines
enddef

# JQL field of the list column at display column vcol of the header line
# (KEY, STATUS, ...), or '' if there is none.
export def ColumnAt(header: string, vcol: number): string
  var name = ''
  var start = 0
  while true
    const [word, s, e] = matchstrpos(header, '\S\+', start)
    if s < 0 || s >= vcol
      break
    endif
    name = word
    start = e
  endwhile
  return index(LIST_COLUMNS, name) >= 0 ? tolower(name) : ''
enddef

# jql with its ORDER BY replaced by "ORDER BY field ASC", or DESC if it is
# already ordered by field ascending.
export def SortJql(jql: string, field: string): string
  # The last ORDER BY and everything after it.
  const pat = '\c\s*\<order\s\+by\>\%(.*\<order\s\+by\>\)\@!\(.*\)$'
  const order = trim(get(matchlist(jql, pat), 1, ''))
  const dir = order =~? '^' .. field .. '\s\+asc\>' ? 'DESC' : 'ASC'
  const base = trim(substitute(jql, pat, '', ''))
  return (empty(base) ? '' : base .. ' ') .. 'ORDER BY ' .. field .. ' ' .. dir
enddef

export def DetailLines(issue: dict<any>): list<string>
  const key = Str(get(issue, 'key', ''))
  const f = get(issue, 'fields', {})
  const labels = get(f, 'labels', [])

  var lines = ['# ' .. key .. ': ' .. Str(get(f, 'summary', '')), '']
  for [label, value] in [
      ['Type', Name(get(f, 'issuetype', {}))],
      ['Status', Name(get(f, 'status', {}))],
      ['Priority', Name(get(f, 'priority', {}))],
      ['Assignee', Name(get(f, 'assignee', {}))],
      ['Reporter', Name(get(f, 'reporter', {}))],
      ['Created', Date(get(f, 'created', ''))],
      ['Updated', Date(get(f, 'updated', ''))],
      ['Labels', type(labels) == v:t_list ? join(labels, ', ') : ''],
      ['URL', jira.BrowseUrl(key)],
    ]
    add(lines, '- ' .. Pad(label .. ':', 10) .. (empty(value) ? '-' : value))
  endfor

  extend(lines, ['', '## Description', ''])
  const description = adf.ToLines(get(f, 'description', {}))
  extend(lines, empty(description) ? ['(no description)'] : description)

  const comment = get(f, 'comment', {})
  const comments = type(comment) == v:t_dict ? get(comment, 'comments', []) : []
  extend(lines, ['', '## Comments (' .. len(comments) .. ')'])
  for c in comments
    extend(lines, ['', '### ' .. Name(get(c, 'author', {})) .. ' - '
      .. Date(get(c, 'created', '')), ''])
    extend(lines, adf.ToLines(get(c, 'body', {})))
  endfor
  return lines
enddef

# ----------------------------------------------------------------------------
# Buffers

def ErrorMsg(msg: string)
  redraw
  echohl ErrorMsg
  echomsg msg
  echohl None
enddef

# Opens buffer name in the current window and fills it with lines.
# opencmd: 'edit' or 'split'.
def Show(opencmd: string, name: string, lines: list<string>, state: dict<any>)
  if opencmd == 'edit' && &modified && !&hidden && bufname() != name
    execute 'silent keepalt split ' .. fnameescape(name)
  else
    execute 'silent keepalt ' .. opencmd .. ' ' .. fnameescape(name)
  endif
  const first = !exists('b:jira')
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
  setlocal modifiable
  silent :%delete _
  setline(1, lines)
  setlocal nomodifiable nomodified
  b:jira = state
  if first
    nnoremap <buffer> <nowait> <silent> r <ScriptCmd>Refresh()<CR>
    nnoremap <buffer> <nowait> <silent> q <ScriptCmd>Close()<CR>
    nnoremap <buffer> <nowait> <silent> e <ScriptCmd>Edit()<CR>
    nnoremap <buffer> <nowait> <silent> c <ScriptCmd>Comment()<CR>
    nnoremap <buffer> <nowait> <silent> s <ScriptCmd>Transition()<CR>
    if state.kind == 'list'
      nnoremap <buffer> <nowait> <silent> <CR> <ScriptCmd>OpenUnderCursor()<CR>
      nnoremap <buffer> <nowait> <silent> o <ScriptCmd>Sort()<CR>
      setlocal filetype=jiraissues
    else
      setlocal filetype=markdown
    endif
  endif
enddef

def ShowList(opencmd: string, jql: string): bool
  echo 'jira: searching...'
  try
    const lines = ListLines(jql, Search(jql))
    Show(opencmd, LIST_BUFFER, lines, {kind: 'list', jql: jql})
  catch /^jira:/
    ErrorMsg(v:exception)
    return false
  endtry
  redraw | echo ''
  return true
enddef

def ShowIssue(opencmd: string, key: string): bool
  echo 'jira: loading ' .. key .. '...'
  try
    const lines = DetailLines(Fetch(key))
    Show(opencmd, 'jira://issue/' .. key, lines, {kind: 'issue', key: key})
  catch /^jira:/
    ErrorMsg(v:exception)
    return false
  endtry
  redraw | echo ''
  return true
enddef

# Window in the current tab showing an issue detail buffer, or 0.
def DetailWindow(): number
  for w in gettabinfo(tabpagenr())[0].windows
    const vars = getbufvar(winbufnr(w), 'jira', {})
    if get(vars, 'kind', '') == 'issue'
      return w
    endif
  endfor
  return 0
enddef

def KeyUnderCursor(): string
  return matchstr(getline('.'), '^\a[A-Za-z0-9_]*-\d\+\ze\s')
enddef

def OpenUnderCursor()
  const key = KeyUnderCursor()
  if empty(key)
    return
  endif
  const win = DetailWindow()
  if win != 0
    win_gotoid(win)
    ShowIssue('edit', key)
  else
    ShowIssue('split', key)
  endif
enddef

def Refresh()
  const state = get(b:, 'jira', {})
  const pos = getcurpos()
  if get(state, 'kind', '') == 'list'
    ShowList('edit', state.jql)
  elseif get(state, 'kind', '') == 'issue'
    ShowIssue('edit', state.key)
  endif
  setpos('.', pos)
enddef

# Searches again, ordered by the column under the cursor (see SortJql()).
def Sort()
  const field = ColumnAt(getline(3), virtcol('.'))
  if empty(field)
    return
  endif
  const pos = getcurpos()
  ShowList('edit', SortJql(b:jira.jql, field))
  setpos('.', pos)
enddef

def Close()
  if winnr('$') > 1
    close
  elseif bufnr('#') > 0 && bufexists(bufnr('#'))
    buffer #
  else
    enew
  endif
enddef

# ----------------------------------------------------------------------------
# Updating issues

# The issue to act on: the argument, else the issue shown in the current
# jira buffer, else the issue under the cursor in the list.
def ContextKey(arg: string): string
  if !empty(trim(arg))
    return NormalizeKey(arg)
  endif
  const state = get(b:, 'jira', {})
  if has_key(state, 'key')
    return state.key
  elseif get(state, 'kind', '') == 'list' && !empty(KeyUnderCursor())
    return KeyUnderCursor()
  endif
  throw 'jira: no issue: give a key or use this in a jira buffer'
enddef

# Re-fetches the list and the detail buffer of key in the current tab.
def RefreshViews(key: string)
  const current = win_getid()
  for w in gettabinfo(tabpagenr())[0].windows
    const state = getbufvar(winbufnr(w), 'jira', {})
    if get(state, 'kind', '') == 'list'
        || (get(state, 'kind', '') == 'issue' && state.key == key)
      win_gotoid(w)
      Refresh()
    endif
  endfor
  win_gotoid(current)
enddef

# Opens a writable scratch buffer; :w calls SaveEditor().
def OpenEditor(name: string, lines: list<string>, state: dict<any>, hint: string)
  const existing = bufwinid(name)
  if existing != -1
    win_gotoid(existing)
    return
  endif
  execute 'silent keepalt split ' .. fnameescape(name)
  setlocal buftype=acwrite bufhidden=wipe noswapfile nobuflisted
  setlocal filetype=markdown
  setline(1, lines)
  setlocal nomodified
  b:jira = state
  autocmd BufWriteCmd <buffer> SaveEditor()
  redraw
  echo hint
enddef

# Strips leading and trailing blank lines.
def TrimLines(lines: list<string>): list<string>
  var first = 0
  var last = len(lines) - 1
  while first <= last && lines[first] =~ '^\s*$'
    first += 1
  endwhile
  while last >= first && lines[last] =~ '^\s*$'
    last -= 1
  endwhile
  return lines[first : last]
enddef

# Splits an edit buffer into summary (line 1) and description (after the
# first blank line, like a git commit message).
export def ParseEditLines(lines: list<string>): dict<any>
  const summary = trim(get(lines, 0, ''))
  const rest = lines[1 :]
  return {
    summary: summary,
    description: TrimLines(get(rest, 0, '') =~ '^\s*$' ? rest[1 :] : rest),
  }
enddef

# Fields that changed between the original and the edited text.
export def ChangedFields(orig: dict<any>, edited: dict<any>): dict<any>
  var fields: dict<any> = {}
  if edited.summary != orig.summary
    fields.summary = edited.summary
  endif
  if edited.description != orig.description
    fields.description = adf.FromLines(edited.description)
  endif
  return fields
enddef

# Deep equality that is false (not an error) for values of different types,
# e.g. a description dict versus null.
def Same(a: any, b: any): bool
  return type(a) == type(b) && a == b
enddef

# Names of the fields about to be saved that were changed in Jira since
# the editor was opened. original holds the values Jira returned at that
# time, current the values Jira returns now. The description is compared
# in Jira's own format, so formatting-only changes are noticed too.
export def Conflicts(original: dict<any>, current: dict<any>, fields: dict<any>): list<string>
  return keys(fields)->sort()->filter((_, name) =>
    !Same(get(original, name, null), get(current, name, null)))
enddef

def CheckConflicts(state: dict<any>, fields: dict<any>)
  const current = get(jira.Api('GET', '/rest/api/3/issue/' .. state.key
    .. '?fields=' .. join(keys(fields)->sort(), ',')), 'fields', {})
  const conflicts = Conflicts(state.original, current, fields)
  if !empty(conflicts)
    throw 'jira: ' .. state.key .. ' ' .. join(conflicts, ' and ')
      .. ' changed in Jira since you opened this editor. Your text is kept.'
      .. ' :w! overwrites, or :q! and press e to start from the current version'
  endif
enddef

def SaveEditor()
  const state = b:jira
  const lines = getline(1, '$')
  const force = v:cmdbang
  try
    if state.kind == 'edit'
      const edited = ParseEditLines(lines)
      if empty(edited.summary)
        throw 'jira: summary (line 1) must not be empty'
      endif
      const fields = ChangedFields(state, edited)
      if empty(fields)
        setlocal nomodified
        echo 'jira: no changes'
        return
      endif
      if !force
        CheckConflicts(state, fields)
      endif
      jira.Api('PUT', '/rest/api/3/issue/' .. state.key, json_encode({fields: fields}))
    else
      const body = adf.FromLines(TrimLines(lines))
      if body == null
        throw 'jira: empty comment, not posted'
      endif
      jira.Api('POST', '/rest/api/3/issue/' .. state.key .. '/comment',
        json_encode({body: body}))
    endif
  catch /^jira:/
    ErrorMsg(v:exception)
    return
  endtry
  setlocal nomodified
  Close()
  RefreshViews(state.key)
  echomsg 'jira: ' .. state.key .. (state.kind == 'edit' ? ' updated' : ': comment added')
enddef

# :JiraEdit [key] - edit summary and description.
export def Edit(arg: string = '')
  try
    const key = ContextKey(arg)
    if !jira.EnsureCredentials()
      return
    endif
    const f = get(Fetch(key), 'fields', {})
    const summary = Str(get(f, 'summary', ''))
    const description = adf.ToLines(get(f, 'description', {}))
    # original: the values as Jira returned them, for the conflict check.
    OpenEditor('jira://edit/' .. key, [summary, ''] + description,
      {kind: 'edit', key: key, summary: summary, description: description,
        original: {summary: get(f, 'summary', null),
          description: get(f, 'description', null)}},
      'Line 1: summary, from line 3: description. :w saves, :q! cancels')
  catch /^jira:/
    ErrorMsg(v:exception)
  endtry
enddef

# :JiraComment [key] - write a new comment.
export def Comment(arg: string = '')
  try
    const key = ContextKey(arg)
    if !jira.EnsureCredentials()
      return
    endif
    OpenEditor('jira://comment/' .. key, [], {kind: 'comment', key: key},
      'Write a comment on ' .. key .. '. :w posts, :q! cancels')
  catch /^jira:/
    ErrorMsg(v:exception)
  endtry
enddef

# Menu lines for the available transitions.
export def TransitionChoices(key: string, transitions: list<any>): list<string>
  var choices = ['Change status of ' .. key .. ':']
  for i in range(len(transitions))
    const t = transitions[i]
    const name = Str(get(t, 'name', ''))
    const to = Name(get(t, 'to', {}))
    add(choices, (i + 1) .. '. ' .. name .. (empty(to) || to == name ? '' : ' -> ' .. to))
  endfor
  return choices
enddef

# Index of the transition whose name or target status equals name
# (ignoring case), or -1.
export def FindTransition(transitions: list<any>, name: string): number
  for i in range(len(transitions))
    const t = transitions[i]
    if Str(get(t, 'name', '')) ==? name || Name(get(t, 'to', {})) ==? name
      return i
    endif
  endfor
  return -1
enddef

# :JiraTransition [key] [status] - change the status via a workflow
# transition. Without status, a menu of the allowed transitions is shown.
export def Transition(arg: string = '')
  try
    const first = matchstr(arg, '^\s*\zs\S\+')
    const has_key = first =~ KEY_PATTERN
    const key = ContextKey(has_key ? first : '')
    const status = trim(has_key ? substitute(arg, '^\s*\S\+', '', '') : arg)
    if !jira.EnsureCredentials()
      return
    endif
    const transitions = get(jira.Api('GET', '/rest/api/3/issue/' .. key
      .. '/transitions'), 'transitions', [])
    if empty(transitions)
      throw 'jira: no transitions available for ' .. key
    endif
    var index: number
    if empty(status)
      index = inputlist(TransitionChoices(key, transitions)) - 1
      if index < 0 || index >= len(transitions)
        redraw
        echo 'jira: cancelled'
        return
      endif
    else
      index = FindTransition(transitions, status)
      if index < 0
        throw 'jira: "' .. status .. '" is not available for ' .. key .. '; choose from: '
          .. join(transitions->mapnew((_, t) => Str(get(t, 'name', ''))), ', ')
      endif
    endif
    const t = transitions[index]
    jira.Api('POST', '/rest/api/3/issue/' .. key .. '/transitions',
      json_encode({transition: {id: t.id}}))
    RefreshViews(key)
    redraw
    const target = Name(get(t, 'to', {}))
    echomsg 'jira: ' .. key .. ' -> ' .. (empty(target) ? Str(get(t, 'name', '')) : target)
  catch /^jira:/
    ErrorMsg(v:exception)
  endtry
enddef

# ----------------------------------------------------------------------------
# Commands

# :JiraIssues [JQL]
export def Issues(jql: string = '')
  if !jira.EnsureCredentials()
    return
  endif
  ShowList('edit', empty(trim(jql)) ? DefaultJql() : trim(jql))
enddef

# :JiraIssue {key}
export def Issue(key: string)
  var k: string
  try
    k = NormalizeKey(key)
  catch /^jira:/
    ErrorMsg(v:exception)
    return
  endtry
  if !jira.EnsureCredentials()
    return
  endif
  ShowIssue('edit', k)
enddef
