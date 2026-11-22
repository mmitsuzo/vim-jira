vim9script
# Tests for the issue list / detail views and the ADF converter.

import autoload 'jira/issue.vim'
import autoload 'jira/adf.vim'
import './helper.vim' as h

def Doc(...blocks: list<any>): dict<any>
  return {type: 'doc', version: 1, content: blocks}
enddef

def P(...inline: list<any>): dict<any>
  return {type: 'paragraph', content: inline}
enddef

def T(text: string, marks: list<any> = []): dict<any>
  return empty(marks) ? {type: 'text', text: text} : {type: 'text', text: text, marks: marks}
enddef

const SEARCH_RESULT = {
  isLast: true,
  issues: [
    {key: 'ABC-1', fields: {summary: 'First issue',
      status: {name: 'To Do'}, assignee: {displayName: 'Alice'}}},
    {key: 'ABC-12', fields: {summary: '日本語の課題',
      status: {name: '進行中'}, assignee: v:null}},
  ],
}

const ISSUE = {
  key: 'ABC-1',
  fields: {
    summary: 'First issue',
    issuetype: {name: 'Bug'},
    status: {name: 'To Do'},
    priority: {name: 'High'},
    assignee: {displayName: 'Alice'},
    reporter: {displayName: 'Bob'},
    created: '2026-11-01T10:20:30.000+0900',
    updated: '2026-11-02T08:00:00.000+0900',
    labels: ['ui', 'urgent'],
    description: Doc(P(T('Hello '), T('world', [{type: 'strong'}]))),
    comment: {comments: [
      {author: {displayName: 'Carol'}, created: '2026-11-03T09:00:00.000+0900',
        body: Doc(P(T('Looks good')))},
    ]},
  },
}

# --- ADF --------------------------------------------------------------------

def g:Test_adf_paragraphs_and_breaks()
  assert_equal([], adf.ToLines(v:null))
  assert_equal(['a', '', 'b', 'c'], adf.ToLines(Doc(
    P(T('a')), P(), P(T('b'), {type: 'hardBreak'}, T('c')))))
enddef

def g:Test_adf_marks_and_inline_nodes()
  assert_equal(['`x` site <https://e.com> @Alice :smile: https://card [DONE]'],
    adf.ToLines(Doc(P(
      T('x', [{type: 'code'}]), T(' '),
      T('site', [{type: 'link', attrs: {href: 'https://e.com'}}]), T(' '),
      {type: 'mention', attrs: {text: '@Alice'}}, T(' '),
      {type: 'emoji', attrs: {shortName: ':smile:'}}, T(' '),
      {type: 'inlineCard', attrs: {url: 'https://card'}}, T(' '),
      {type: 'status', attrs: {text: 'DONE'}}))))
enddef

def g:Test_adf_blocks()
  const doc = Doc(
    {type: 'heading', attrs: {level: 1}, content: [T('Title')]},
    {type: 'bulletList', content: [
      {type: 'listItem', content: [P(T('one')),
        {type: 'bulletList', content: [{type: 'listItem', content: [P(T('nested'))]}]}]},
      {type: 'listItem', content: [P(T('two'))]}]},
    {type: 'orderedList', attrs: {order: 3}, content: [
      {type: 'listItem', content: [P(T('three'))]}]},
    {type: 'codeBlock', attrs: {language: 'sh'}, content: [T("ls\npwd")]},
    {type: 'blockquote', content: [P(T('quoted'))]},
    {type: 'rule'},
    {type: 'table', content: [
      {type: 'tableRow', content: [
        {type: 'tableHeader', content: [P(T('A'))]},
        {type: 'tableHeader', content: [P(T('B'))]}]}]},
    {type: 'mediaSingle', content: [{type: 'media'}]},
    {type: 'unknownBlock', content: [P(T('fallback'))]})
  assert_equal([
    '### Title', '',
    '- one', '  - nested', '- two', '',
    '3. three', '',
    '```sh', 'ls', 'pwd', '```', '',
    '> quoted', '',
    '---', '',
    '| A | B |', '',
    '[attachment]', '',
    'fallback',
  ], adf.ToLines(doc))
enddef

# --- formatting ---------------------------------------------------------------

def g:Test_normalize_key()
  assert_equal('ABC-1', issue.NormalizeKey(' abc-1 '))
  assert_equal('A1_B-22', issue.NormalizeKey('A1_B-22'))
  for bad in ['', 'ABC', '1ABC-1', 'ABC-1/../x', 'ABC-1?x=1']
    h.AssertThrows(() => issue.NormalizeKey(bad), 'invalid issue key')
  endfor
enddef

def g:Test_list_lines()
  const lines = issue.ListLines('project = ABC', SEARCH_RESULT)
  assert_equal([
    'JQL: project = ABC',
    '',
    'KEY     STATUS  ASSIGNEE  SUMMARY',
    'ABC-1   To Do   Alice     First issue',
    'ABC-12  進行中  -         日本語の課題',
  ], lines)
enddef

def g:Test_column_at()
  const header = 'KEY     STATUS  ASSIGNEE  SUMMARY'
  assert_equal('key', issue.ColumnAt(header, 1))
  assert_equal('key', issue.ColumnAt(header, 8))
  assert_equal('status', issue.ColumnAt(header, 9))
  assert_equal('assignee', issue.ColumnAt(header, 17))
  assert_equal('summary', issue.ColumnAt(header, 99))
  assert_equal('', issue.ColumnAt('(no issues)', 1))
enddef

def g:Test_sort_jql()
  assert_equal('project = A ORDER BY status ASC',
    issue.SortJql('project = A', 'status'))
  assert_equal('project = A ORDER BY key ASC',
    issue.SortJql('project = A order by updated DESC, key', 'key'))
  assert_equal('project = A ORDER BY key DESC',
    issue.SortJql('project = A ORDER BY key ASC', 'key'))
  assert_equal('project = A ORDER BY key ASC',
    issue.SortJql('project = A ORDER BY key DESC', 'key'))
  assert_equal('ORDER BY summary ASC', issue.SortJql('ORDER BY created', 'summary'))
  # Only the last ORDER BY is replaced
  assert_equal('text ~ "order by" ORDER BY key ASC',
    issue.SortJql('text ~ "order by" ORDER BY created', 'key'))
enddef

def g:Test_list_lines_empty_and_more()
  assert_equal(['JQL: x', '', '(no issues)'],
    issue.ListLines('x', {issues: [], isLast: true}))
  const lines = issue.ListLines('x', {issues: [], isLast: false})
  assert_match('^-- more issues exist', lines[-1])
enddef

def g:Test_detail_lines()
  g:jira_url = 'https://x.atlassian.net'
  const lines = issue.DetailLines(ISSUE)
  unlet g:jira_url
  assert_equal([
    '# ABC-1: First issue',
    '',
    '- Type:     Bug',
    '- Status:   To Do',
    '- Priority: High',
    '- Assignee: Alice',
    '- Reporter: Bob',
    '- Created:  2026-11-01 10:20',
    '- Updated:  2026-11-02 08:00',
    '- Labels:   ui, urgent',
    '- URL:      https://x.atlassian.net/browse/ABC-1',
    '',
    '## Description',
    '',
    'Hello world',
    '',
    '## Comments (1)',
    '',
    '### Carol - 2026-11-03 09:00',
    '',
    'Looks good',
  ], lines)
enddef

def g:Test_detail_lines_missing_fields()
  const lines = issue.DetailLines({key: 'ABC-2', fields: {summary: 'x',
    assignee: v:null, description: v:null, labels: []}})
  assert_true(index(lines, '- Assignee: -') >= 0)
  assert_true(index(lines, '(no description)') >= 0)
  assert_true(index(lines, '## Comments (0)') >= 0)
enddef

# --- paging, against the fake curl -------------------------------------------

def Page(keys: list<string>, token: string = ''): dict<any>
  var page: dict<any> = {issues: keys->mapnew((_, k) => ({key: k, fields: {}}))}
  if empty(token)
    page.isLast = true
  else
    page.isLast = false
    page.nextPageToken = token
  endif
  return page
enddef

def g:Test_search_follows_next_page_token()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()
  unlet! g:jira_max_results
  h.RespondSequence([Page(['A-1', 'A-2'], 'tok1'), Page(['A-3'], 'tok2'), Page(['A-4'])])
  const result = issue.Search('project = A')
  assert_equal(['A-1', 'A-2', 'A-3', 'A-4'], result.issues->mapnew((_, i) => i.key))
  assert_true(result.isLast)
  assert_equal(3, h.RequestCount(dir))
  assert_notmatch('nextPageToken', join(h.LastConfig(dir, 1)))
  assert_match('maxResults.*100', join(h.LastConfig(dir, 1)))
  assert_match('nextPageToken.*tok1', join(h.LastConfig(dir, 2)))
  assert_match('nextPageToken.*tok2', join(h.LastConfig(dir, 3)))
  h.TeardownFakeCurl(dir)
enddef

def g:Test_search_respects_max_results()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()
  g:jira_max_results = 3
  h.RespondSequence([Page(['A-1', 'A-2'], 'tok1'), Page(['A-3', 'A-4'], 'tok2')])
  const result = issue.Search('x')
  assert_equal(['A-1', 'A-2', 'A-3'], result.issues->mapnew((_, i) => i.key))
  assert_false(result.isLast)
  assert_equal(2, h.RequestCount(dir))
  assert_match('maxResults.*3', join(h.LastConfig(dir, 1)))
  assert_match('maxResults.*1', join(h.LastConfig(dir, 2)))

  # 0 means no limit
  g:jira_max_results = 0
  h.RespondSequence([Page(['A-1'], 'tok1'), Page(['A-2'])])
  assert_equal(2, len(issue.Search('x').issues))
  assert_match('maxResults.*100', join(h.LastConfig(dir, 1)))
  unlet g:jira_max_results
  h.TeardownFakeCurl(dir)
enddef

# --- buffers, against the fake curl ----------------------------------------

def g:Test_issues_and_detail_buffers()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()
  only!
  enew!

  # :JiraIssues with the default JQL
  h.Respond(SEARCH_RESULT)
  JiraIssues
  assert_equal('jira://issues', bufname())
  assert_equal('jiraissues', &filetype)
  assert_false(&modifiable)
  assert_equal('JQL: ' .. issue.DefaultJql(), getline(1))
  assert_equal('KEY     STATUS  ASSIGNEE  SUMMARY', getline(3))
  assert_equal('ABC-1   To Do   Alice     First issue', getline(4))
  var cfg = h.LastConfig(dir)
  assert_true(index(cfg, 'request = "POST"') >= 0)
  assert_true(index(cfg, 'url = "https://x.atlassian.net/rest/api/3/search/jql"') >= 0)
  assert_match('data-binary = .*currentUser()', join(cfg, "\n"))

  # o sorts by the column under the cursor; again reverses the order
  const jql = getline(1)
  cursor(4, 9)
  normal o
  assert_equal('JQL: assignee = currentUser() AND resolution = Unresolved'
    .. ' ORDER BY status ASC', getline(1))
  assert_match('data-binary = .*ORDER BY status ASC', join(h.LastConfig(dir), "\n"))
  assert_equal([4, 9], [line('.'), col('.')])
  normal o
  assert_match('ORDER BY status DESC$', getline(1))
  # r keeps the sort order
  normal r
  assert_match('ORDER BY status DESC$', getline(1))
  # sorting and refreshing keep the syntax highlighting
  assert_equal('jiraIssuesKey', synIDattr(synID(4, 1, 1), 'name'))
  JiraIssues
  assert_equal(jql, getline(1))

  # <CR> on the JQL or the column header does nothing; on an issue opens
  # the detail in a split
  for l in [1, 3]
    execute ':' .. l
    execute "normal \<CR>"
    assert_equal(1, winnr('$'))
  endfor
  :4
  h.Respond(ISSUE)
  execute "normal \<CR>"
  assert_equal(2, winnr('$'))
  assert_equal('jira://issue/ABC-1', bufname())
  assert_equal('markdown', &filetype)
  assert_equal('# ABC-1: First issue', getline(1))
  cfg = h.LastConfig(dir)
  assert_match('url = "https://x.atlassian.net/rest/api/3/issue/ABC-1?fields=summary,',
    join(cfg, "\n"))

  # Opening another issue from the list reuses the detail window
  wincmd p
  assert_equal('jira://issues', bufname())
  :5
  h.Respond({key: 'ABC-12', fields: {summary: '日本語の課題'}})
  execute "normal \<CR>"
  assert_equal(2, winnr('$'))
  assert_equal('# ABC-12: 日本語の課題', getline(1))

  # r refreshes, q closes the detail window
  h.Respond({key: 'ABC-12', fields: {summary: 'Renamed'}})
  normal r
  assert_equal('# ABC-12: Renamed', getline(1))
  normal q
  assert_equal(1, winnr('$'))
  assert_equal('jira://issues', bufname())

  # :JiraIssues with custom JQL, :JiraIssue with a key
  h.Respond({issues: [], isLast: true})
  JiraIssues project = "ABC"
  assert_equal('JQL: project = "ABC"', getline(1))
  assert_match('data-binary = .*project = \\\\\\"ABC\\\\\\"', join(h.LastConfig(dir), "\n"))
  h.Respond(ISSUE)
  JiraIssue abc-1
  assert_equal('jira://issue/ABC-1', bufname())

  # API errors are reported and leave the current buffer alone
  h.Respond({errorMessages: ["Error in the JQL Query"]}, 400)
  # (messages are not kept in -es mode, so check the effects instead)
  silent JiraIssues bad jql
  assert_match('bad jql', join(h.LastConfig(dir), "\n"))
  assert_equal('jira://issue/ABC-1', bufname())
  assert_equal('# ABC-1: First issue', getline(1))
  h.AssertThrows(() => issue.Search('bad jql'), 'HTTP 400: Error in the JQL Query')

  only!
  enew!
  h.TeardownFakeCurl(dir)
enddef
