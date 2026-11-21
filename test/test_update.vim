vim9script
# Tests for editing issues, adding comments and changing the status.

import autoload 'jira/issue.vim'
import autoload 'jira/adf.vim'
import './helper.vim' as h

def MakeIssue(summary: string, description: any = null): dict<any>
  return {key: 'ABC-1', fields: {summary: summary, description: description,
    status: {name: 'To Do'}}}
enddef

def P(text: string): dict<any>
  return {type: 'paragraph', content: [{type: 'text', text: text}]}
enddef

# --- text -> ADF --------------------------------------------------------------

def g:Test_adf_from_lines_empty()
  assert_equal(null, adf.FromLines([]))
  assert_equal(null, adf.FromLines(['', '  ']))
enddef

def g:Test_adf_from_lines_paragraphs()
  assert_equal({type: 'doc', version: 1, content: [
      {type: 'paragraph', content: [
        {type: 'text', text: 'a'}, {type: 'hardBreak'}, {type: 'text', text: 'b'}]},
      P('c')]},
    adf.FromLines(['a', 'b', '', 'c']))
enddef

def g:Test_adf_round_trip()
  # Text produced by ToLines() converts back to equivalent ADF.
  const lines = [
    '### Title', '',
    'Some text', 'second line', '',
    '- one', '  - nested', '- two', '',
    '3. three', '4. four', '',
    '```sh', 'ls', '', 'pwd', '```', '',
    '> quoted', '',
    '---', '',
    'end',
  ]
  const doc = adf.FromLines(lines)
  assert_equal(lines, adf.ToLines(doc))
  assert_equal({type: 'heading', attrs: {level: 1},
    content: [{type: 'text', text: 'Title'}]}, doc.content[0])
  assert_equal({type: 'codeBlock', attrs: {language: 'sh'},
    content: [{type: 'text', text: "ls\n\npwd"}]}, doc.content[4])
enddef

# --- edit buffer parsing ----------------------------------------------------

def g:Test_parse_edit_lines()
  assert_equal({summary: 'Title', description: ['a', '', 'b']},
    issue.ParseEditLines([' Title ', '', '', 'a', '', 'b', '', '']))
  assert_equal({summary: 'Title', description: []}, issue.ParseEditLines(['Title']))
  # A missing blank line after the summary is tolerated.
  assert_equal({summary: 'T', description: ['x']}, issue.ParseEditLines(['T', 'x']))
enddef

def g:Test_changed_fields()
  const orig = {summary: 'S', description: ['d']}
  assert_equal({}, issue.ChangedFields(orig, {summary: 'S', description: ['d']}))
  assert_equal({summary: 'S2'}, issue.ChangedFields(orig, {summary: 'S2', description: ['d']}))
  const f = issue.ChangedFields(orig, {summary: 'S', description: ['new']})
  assert_equal(['description'], keys(f))
  assert_equal([P('new')], f.description.content)
  # Clearing the description sends null.
  assert_equal({description: null}, issue.ChangedFields(orig, {summary: 'S', description: []}))
enddef

def g:Test_transition_choices()
  assert_equal(['Change status of ABC-1:', '1. Start -> In Progress', '2. Done'],
    issue.TransitionChoices('ABC-1', [
      {id: '11', name: 'Start', to: {name: 'In Progress'}},
      {id: '31', name: 'Done', to: {name: 'Done'}}]))
enddef

def g:Test_find_transition()
  const ts = [{id: '11', name: 'Start', to: {name: 'In Progress'}},
    {id: '31', name: 'Done', to: {name: 'Done'}}]
  assert_equal(0, issue.FindTransition(ts, 'start'))
  assert_equal(0, issue.FindTransition(ts, 'IN PROGRESS'))
  assert_equal(1, issue.FindTransition(ts, 'Done'))
  assert_equal(-1, issue.FindTransition(ts, 'Nope'))
enddef

# --- against the fake curl ----------------------------------------------------

def g:Test_edit_issue()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()
  only!
  enew!

  h.Respond(MakeIssue('Old title', {type: 'doc', version: 1, content: [P('Old text')]}))
  JiraIssue ABC-1
  JiraEdit
  assert_equal('jira://edit/ABC-1', bufname())
  assert_equal(2, winnr('$'))
  assert_equal('acwrite', &buftype)
  assert_equal(['Old title', '', 'Old text'], getline(1, '$'))

  # Unchanged: nothing is sent
  h.RespondSequence([])
  silent write
  assert_equal(0, h.RequestCount(dir))

  # Summary only: description is not sent, so its formatting is kept.
  # Requests: conflict check, PUT, refresh.
  const desc = {type: 'doc', version: 1, content: [P('Old text')]}
  setline(1, 'New title')
  h.RespondSequence([MakeIssue('Old title', desc), '', MakeIssue('New title', desc)])
  silent write
  assert_equal(3, h.RequestCount(dir))
  const check = join(h.LastConfig(dir, 1), "\n")
  assert_match('request = "GET"', check)
  assert_match('issue/ABC-1?fields=summary"', check)
  const put = join(h.LastConfig(dir, 2), "\n")
  assert_match('request = "PUT"', put)
  assert_match('url = "https://x.atlassian.net/rest/api/3/issue/ABC-1"', put)
  assert_match('New title', put)
  assert_notmatch('description', put)
  # Editor closed, detail refreshed
  assert_equal(1, winnr('$'))
  assert_equal('jira://issue/ABC-1', bufname())
  assert_equal('# ABC-1: New title', getline(1))
  assert_equal(-1, bufnr('jira://edit/ABC-1'))

  # Description
  h.Respond(MakeIssue('New title', desc))
  JiraEdit
  setline(3, ['New text', '', '- item'])
  h.RespondSequence([MakeIssue('New title', desc), '', MakeIssue('New title')])
  silent write
  assert_match('issue/ABC-1?fields=description"', join(h.LastConfig(dir, 1)))
  const put2 = join(h.LastConfig(dir, 2), "\n")
  assert_match('bulletList', put2)
  assert_match('New text', put2)
  assert_notmatch('summary', put2)

  # Empty summary is rejected and the editor stays open
  JiraEdit
  setline(1, '')
  h.RespondSequence([])
  silent write
  assert_equal(0, h.RequestCount(dir))
  assert_equal('jira://edit/ABC-1', bufname())
  assert_true(&modified)
  bwipe!

  only!
  enew!
  h.TeardownFakeCurl(dir)
enddef

def g:Test_conflicts()
  const doc = {type: 'doc', content: [P('x')]}
  const original = {summary: 'S', description: doc}
  assert_equal([], issue.Conflicts(original, {summary: 'S', description: doc},
    {summary: 'new', description: {}}))
  assert_equal(['summary'], issue.Conflicts(original, {summary: 'T', description: doc},
    {summary: 'new'}))
  # Only fields being saved are checked
  assert_equal([], issue.Conflicts(original, {summary: 'T', description: doc},
    {description: {}}))
  # null vs dict does not raise a type error
  assert_equal(['description'], issue.Conflicts(original, {description: null},
    {description: {}}))
  assert_equal([], issue.Conflicts({description: null}, {description: null},
    {description: {}}))
enddef

def g:Test_edit_conflict()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()
  only!
  enew!
  const desc = {type: 'doc', version: 1, content: [P('Old text')]}
  # Same text, but someone made it bold: invisible in Vim, still a conflict
  const bold = {type: 'doc', version: 1, content: [{type: 'paragraph', content: [
    {type: 'text', text: 'Old text', marks: [{type: 'strong'}]}]}]}

  h.Respond(MakeIssue('Title', desc))
  JiraIssue ABC-1
  JiraEdit
  setline(3, 'My text')
  h.RespondSequence([MakeIssue('Title', bold)])
  silent write
  assert_equal(1, h.RequestCount(dir))
  assert_equal('jira://edit/ABC-1', bufname())
  assert_true(&modified)
  assert_equal('My text', getline(3))

  # A summary-only save is not blocked by the description change
  setline(3, 'Old text')
  setline(1, 'New')
  h.RespondSequence([MakeIssue('Title', bold), '', MakeIssue('New', bold)])
  silent write
  assert_equal(3, h.RequestCount(dir))
  assert_notmatch('description', join(h.LastConfig(dir, 2)))
  assert_equal('jira://issue/ABC-1', bufname())

  # Summary changed by someone else: refused; :w! overwrites without checking
  h.Respond(MakeIssue('Title', desc))
  JiraEdit
  setline(1, 'Mine')
  h.RespondSequence([MakeIssue('Theirs', desc)])
  silent write
  assert_equal(1, h.RequestCount(dir))
  assert_true(&modified)
  h.RespondSequence(['', MakeIssue('Mine', desc)])
  silent write!
  assert_equal(2, h.RequestCount(dir))
  const put = join(h.LastConfig(dir, 1), "\n")
  assert_match('request = "PUT"', put)
  assert_match('Mine', put)
  assert_equal('jira://issue/ABC-1', bufname())

  only!
  enew!
  h.TeardownFakeCurl(dir)
enddef

def g:Test_add_comment()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()
  only!
  enew!

  h.Respond({isLast: true, issues: [{key: 'ABC-1', fields: {summary: 'x'}}]})
  JiraIssues
  :4
  normal c
  assert_equal('jira://comment/ABC-1', bufname())
  assert_equal([''], getline(1, '$'))

  # Empty comment is not posted
  h.RespondSequence([])
  silent write
  assert_equal(0, h.RequestCount(dir))
  assert_equal('jira://comment/ABC-1', bufname())

  setline(1, ['Looks good', 'thanks'])
  h.RespondSequence(['{"id":"1"}', {isLast: true, issues: []}])
  silent write
  const post = join(h.LastConfig(dir, 1), "\n")
  assert_match('request = "POST"', post)
  assert_match('url = "https://x.atlassian.net/rest/api/3/issue/ABC-1/comment"', post)
  assert_match('Looks good.*hardBreak.*thanks', post)
  # Editor closed and the list refreshed
  assert_equal('jira://issues', bufname())
  assert_equal(1, winnr('$'))
  assert_equal(2, h.RequestCount(dir))

  only!
  enew!
  h.TeardownFakeCurl(dir)
enddef

def g:Test_transition()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()
  only!
  enew!

  h.Respond(MakeIssue('x'))
  JiraIssue ABC-1
  const transitions = {transitions: [
    {id: '11', name: 'Start', to: {name: 'In Progress'}},
    {id: '31', name: 'Done', to: {name: 'Done'}}]}

  # By target status name, case-insensitive (the menu needs a terminal)
  h.RespondSequence([transitions, '', MakeIssue('x')])
  silent JiraTransition in progress
  assert_equal(3, h.RequestCount(dir))
  assert_match('url = ".*/rest/api/3/issue/ABC-1/transitions"', join(h.LastConfig(dir, 1)))
  const post = join(h.LastConfig(dir, 2), "\n")
  assert_match('request = "POST"', post)
  assert_match('url = ".*/rest/api/3/issue/ABC-1/transitions"', post)
  assert_match('"id\\":\\"11', post)

  # With an explicit key, by transition name
  enew!
  h.RespondSequence([transitions, ''])
  silent JiraTransition abc-1 Done
  assert_match('"id\\":\\"31', join(h.LastConfig(dir, 2), "\n"))

  # Unknown status: nothing is posted
  h.RespondSequence([transitions])
  silent JiraTransition ABC-1 Nope
  assert_equal(1, h.RequestCount(dir))

  only!
  enew!
  h.TeardownFakeCurl(dir)
enddef

def g:Test_context_key_required()
  only!
  enew!
  # No key and not in a jira buffer: error message, no exception
  silent JiraEdit
  silent JiraComment
  silent JiraTransition
  assert_equal('', bufname())
enddef
