vim9script
# Tests use Vim's built-in assert_*() functions. Each Test_* function is run
# by test/run.vim. Run with:  vim -Nu NONE -i NONE -es -S test/run.vim

import autoload 'jira.vim'
import './helper.vim' as h
const AssertThrows = h.AssertThrows
const ClearCredentials = h.ClearCredentials

def g:Test_version()
  assert_match('^\d\+\.\d\+\.\d\+$', jira.VERSION)
enddef

def g:Test_option_default()
  unlet! g:jira_example
  assert_equal('fallback', jira.Option('example', 'fallback'))
enddef

def g:Test_option_user_value()
  g:jira_example = 'set'
  assert_equal('set', jira.Option('example', 'fallback'))
  unlet g:jira_example
enddef

def g:Test_commands_defined()
  for cmd in ['JiraVersion', 'JiraCheck', 'JiraLogin', 'JiraLogout',
      'JiraIssues', 'JiraIssue', 'JiraEdit', 'JiraComment', 'JiraTransition']
    assert_equal(2, exists(':' .. cmd), cmd)
  endfor
enddef

# --- credentials -----------------------------------------------------------

def g:Test_url_option_and_env()
  ClearCredentials()
  assert_equal('', jira.Url())
  setenv('JIRA_URL', 'https://env.atlassian.net/')
  assert_equal('https://env.atlassian.net', jira.Url())
  g:jira_url = 'https://opt.atlassian.net//'
  assert_equal('https://opt.atlassian.net', jira.Url())
  ClearCredentials()
enddef

def g:Test_user_option_and_env()
  ClearCredentials()
  assert_equal('', jira.User())
  setenv('JIRA_USER', 'env@example.com')
  assert_equal('env@example.com', jira.User())
  g:jira_user = 'opt@example.com'
  assert_equal('opt@example.com', jira.User())
  ClearCredentials()
enddef

def g:Test_token_from_env()
  ClearCredentials()
  assert_equal({token: '', source: ''}, jira.Token())
  setenv('JIRA_API_TOKEN', 'secret')
  assert_equal({token: 'secret', source: 'env'}, jira.Token())
  g:jira_token_env = 'MY_TOKEN'
  assert_equal('', jira.Token().source)
  setenv('MY_TOKEN', 'mine')
  assert_equal({token: 'mine', source: 'env'}, jira.Token())
  ClearCredentials()
enddef

def g:Test_request_requires_settings()
  ClearCredentials()
  AssertThrows(() => jira.Request('GET', '/x'), 'Jira URL is not set')
  g:jira_url = 'https://x.atlassian.net'
  AssertThrows(() => jira.Request('GET', '/x'), 'account email is not set')
  g:jira_user = 'a@example.com'
  AssertThrows(() => jira.Request('GET', '/x'), 'API token is not set')
  ClearCredentials()
enddef

# --- curl config / output parsing -----------------------------------------

def g:Test_curl_config()
  const cfg = jira.CurlConfig('GET', 'https://x.atlassian.net/rest/api/3/myself',
    'a@example.com', 'to"k\en')
  assert_true(index(cfg, 'request = "GET"') >= 0)
  assert_true(index(cfg, 'url = "https://x.atlassian.net/rest/api/3/myself"') >= 0)
  assert_true(index(cfg, 'user = "a@example.com:to\"k\\en"') >= 0)
  assert_true(index(cfg, 'header = "Accept: application/json"') >= 0)
  assert_equal(-1, match(cfg, 'data-binary'))

  const post = jira.CurlConfig('POST', 'u', 'a', 't', '{"a":"b"}')
  assert_true(index(post, 'data-binary = "{\"a\":\"b\"}"') >= 0)
  assert_true(index(post, 'header = "Content-Type: application/json"') >= 0)
enddef

def g:Test_parse_output()
  assert_equal({status: 200, body: '{"a":1}'}, jira.ParseOutput("{\"a\":1}\n200"))
  assert_equal({status: 401, body: "x\ny"}, jira.ParseOutput("x\r\ny\r\n401\r\n"))
  assert_equal({status: 204, body: ''}, jira.ParseOutput("\n204"))
  assert_equal(0, jira.ParseOutput('garbage').status)
enddef

# --- login against a fake curl (Unix-like shells, incl. Git-Bash) ---------

def g:Test_login_with_fake_curl()
  if !h.HasShell()
    return
  endif
  const dir = h.SetupFakeCurl()

  # Success
  h.Respond({displayName: 'Alice', emailAddress: 'a@example.com'})
  const me = jira.Authenticate()
  assert_equal('Alice', me.displayName)
  assert_equal('Alice', jira.CurrentUser().displayName)
  const cfg = h.LastConfig(dir)
  assert_true(index(cfg, 'url = "https://x.atlassian.net/rest/api/3/myself"') >= 0)
  assert_true(index(cfg, 'user = "a@example.com:envtoken"') >= 0)
  assert_match('Login:    Alice', join(jira.CheckReport().lines, "\n"))
  silent JiraLogin

  # Bad credentials
  h.Respond('', 401)
  AssertThrows(() => jira.Authenticate(), 'login failed (HTTP 401)')
  assert_equal({}, jira.CurrentUser())

  # Jira error message is shown
  h.Respond({errorMessages: ['Site is down']}, 503)
  AssertThrows(() => jira.Authenticate(), 'Site is down')

  h.TeardownFakeCurl(dir)
enddef

def g:Test_login_curl_failure()
  ClearCredentials()
  g:jira_url = 'https://x.atlassian.net'
  g:jira_user = 'a@example.com'
  setenv('JIRA_API_TOKEN', 't')
  g:jira_curl = 'no-such-curl-executable'
  AssertThrows(() => jira.Authenticate(), 'curl failed')
  ClearCredentials()
enddef

def g:Test_platform()
  const p = jira.Platform()
  assert_true(index(['msys', 'cygwin', 'windows', 'unix'], p) >= 0, p)
  if has('win32unix') && !empty($MSYSTEM)
    assert_equal('msys', p)
  endif
enddef

def g:Test_curl_option()
  unlet! g:jira_curl
  assert_equal('curl', jira.Curl())
  g:jira_curl = '/usr/bin/curl'
  assert_equal('/usr/bin/curl', jira.Curl())
  unlet g:jira_curl
enddef

def g:Test_check_missing_curl()
  g:jira_curl = 'no-such-curl-executable'
  const report = jira.CheckReport()
  unlet g:jira_curl
  assert_equal(1, report.errors)
  assert_match('\[ERROR\]', join(report.lines))
enddef

def g:Test_check_runs()
  # Must not throw; output goes to messages.
  silent JiraCheck
enddef

def g:Test_help_tags()
  # Every *tag* in the help file must be unique and :helptags must succeed.
  const root = fnamemodify(globpath(&runtimepath, 'doc/jira.txt', 0, 1)[0], ':h')
  const tmp = tempname()
  mkdir(tmp, 'p')
  writefile(readfile(root .. '/jira.txt'), tmp .. '/jira.txt')
  execute 'helptags ' .. fnameescape(tmp)
  const tags = readfile(tmp .. '/tags')->mapnew((_, l) => split(l, "\t")[0])
  assert_true(index(tags, 'jira.txt') >= 0)
  assert_true(index(tags, ':JiraCheck') >= 0)
  for tag in ['g:jira_curl', 'g:jira_url', 'g:jira_user', 'g:jira_token_env',
      'g:jira_timeout', ':JiraLogin', ':JiraLogout', 'jira-login',
      ':JiraIssues', ':JiraIssue', 'jira-issues', 'jira-mappings',
      'g:jira_default_jql', 'g:jira_max_results', 'jira-edit',
      ':JiraEdit', ':JiraComment', ':JiraTransition', 'jira-edit-conflict']
    assert_true(index(tags, tag) >= 0, tag)
  endfor
  delete(tmp, 'rf')
enddef
