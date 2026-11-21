" jira.vim - Work with Jira from Vim
" Entry point: defines commands and mappings only. Logic lives in autoload/.
"
" This legacy-script guard must come before :vim9script so that older Vim
" versions and Neovim (e.g. sharing a vimrc via vim-plug) skip the plugin
" cleanly instead of raising errors.
if exists('g:loaded_jira') || !has('vim9script') || v:version < 900
  finish
endif

vim9script

g:loaded_jira = 1

import autoload 'jira.vim'
import autoload 'jira/issue.vim'

command! -nargs=0 -bar JiraVersion jira.Version()
command! -nargs=0 -bar JiraCheck jira.Check()
command! -nargs=0 -bar JiraLogin jira.Login()
command! -nargs=0 -bar JiraLogout jira.Logout()
command! -nargs=* JiraIssues issue.Issues(<q-args>)
command! -nargs=1 -bar JiraIssue issue.Issue(<q-args>)
command! -nargs=? -bar JiraEdit issue.Edit(<q-args>)
command! -nargs=? -bar JiraComment issue.Comment(<q-args>)
command! -nargs=* -bar JiraTransition issue.Transition(<q-args>)
