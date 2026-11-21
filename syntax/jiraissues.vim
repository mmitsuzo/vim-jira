" Syntax for the :JiraIssues list buffer.
if exists('b:current_syntax')
  finish
endif

syntax match jiraIssuesHeader /^JQL: .*/
syntax match jiraIssuesKey    /^\a[A-Za-z0-9_]*-\d\+\ze\s/
syntax match jiraIssuesNote   /^\%((no issues)\|-- .* --\)$/

highlight default link jiraIssuesHeader Comment
highlight default link jiraIssuesKey    Identifier
highlight default link jiraIssuesNote   Comment

let b:current_syntax = 'jiraissues'
