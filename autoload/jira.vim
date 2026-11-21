vim9script
# Core functions for jira.vim. Loaded lazily on first use.

export const VERSION = '0.1.0'

export def Version(): string
  echo 'jira.vim ' .. VERSION
  return VERSION
enddef

# Returns the value of a user option g:jira_{name}, or default if unset.
export def Option(name: string, default: any): any
  return get(g:, 'jira_' .. name, default)
enddef

# Returns the environment Vim is running in:
#   'msys'    - Git-Bash / MSYS2 Vim on Windows (has('win32unix') + $MSYSTEM)
#   'cygwin'  - Cygwin Vim on Windows
#   'windows' - native Windows Vim/gVim
#   'unix'    - Linux, macOS, WSL, ...
# Detection uses only built-in features; no external command is run.
export def Platform(): string
  if has('win32unix')
    return empty($MSYSTEM) ? 'cygwin' : 'msys'
  elseif has('win32')
    return 'windows'
  endif
  return 'unix'
enddef

# The curl executable used for talking to Jira. curl is the only external
# dependency; it ships with Git for Windows (Git-Bash), Windows 10+, macOS
# and practically every Linux distribution.
export def Curl(): string
  return Option('curl', 'curl')
enddef

# ----------------------------------------------------------------------------
# Credentials (Jira Cloud: account email + API token)

# Session state. The token typed at the prompt lives only in memory.
var session_token = ''
var session_user = ''
var current_user: dict<any> = {}

# Option value, else environment variable, else ''.
def OptionOrEnv(name: string, envname: string): string
  const value = Option(name, '')
  return empty(value) ? getenv(envname) ?? '' : value
enddef

# Jira Cloud site URL without trailing slash, e.g.
# https://example.atlassian.net
export def Url(): string
  return substitute(OptionOrEnv('url', 'JIRA_URL'), '/\+$', '', '')
enddef

export def TokenEnv(): string
  return Option('token_env', 'JIRA_API_TOKEN')
enddef

# Account email: g:jira_user, $JIRA_USER, or what was typed at :JiraLogin.
export def User(): string
  const user = OptionOrEnv('user', 'JIRA_USER')
  return empty(user) ? session_user : user
enddef

# Returns {token, source}; source is 'env', 'session' or ''.
# The environment variable always takes precedence over a typed token.
export def Token(): dict<string>
  const env = getenv(TokenEnv()) ?? ''
  if !empty(env)
    return {token: env, source: 'env'}
  elseif !empty(session_token)
    return {token: session_token, source: 'session'}
  endif
  return {token: '', source: ''}
enddef

export def CurrentUser(): dict<any>
  return current_user
enddef

# ----------------------------------------------------------------------------
# HTTP

# Quotes a value for a curl config file (curl -K).
def ConfigQuote(s: string): string
  return '"' .. escape(s, '\"') .. '"'
enddef

# Builds the curl config passed on stdin. Credentials are put here rather
# than on the command line so they never show up in the process list.
export def CurlConfig(method: string, url: string, user: string,
    token: string, body: string = ''): list<string>
  var lines = [
    'silent',
    'show-error',
    'request = ' .. ConfigQuote(method),
    'url = ' .. ConfigQuote(url),
    'user = ' .. ConfigQuote(user .. ':' .. token),
    'header = "Accept: application/json"',
    'max-time = ' .. Option('timeout', 30),
    'write-out = "\n%{http_code}"',
  ]
  if !empty(body)
    add(lines, 'header = "Content-Type: application/json"')
    add(lines, 'data-binary = ' .. ConfigQuote(body))
  endif
  return lines
enddef

# Splits curl output ("<body>\n<status>") into {status, body}.
export def ParseOutput(output: string): dict<any>
  const text = substitute(output, '\r', '', 'g')
  const m = matchlist(text, '\v^(.*)\n(\d{3})\n*$')
  if empty(m)
    return {status: 0, body: text}
  endif
  return {status: str2nr(m[2]), body: m[1]}
enddef

# Sends a request to the Jira REST API. path is relative to the site URL,
# e.g. '/rest/api/3/myself'. Returns {status, body, json}; throws on
# missing configuration or when curl itself fails.
export def Request(method: string, path: string, body: string = ''): dict<any>
  const url = Url()
  if empty(url)
    throw 'jira: Jira URL is not set (g:jira_url or $JIRA_URL)'
  endif
  const user = User()
  if empty(user)
    throw 'jira: account email is not set (g:jira_user or $JIRA_USER)'
  endif
  const token = Token().token
  if empty(token)
    throw 'jira: API token is not set ($' .. TokenEnv() .. ' or :JiraLogin)'
  endif

  const config = CurlConfig(method, url .. path, user, token, body)
  const output = system(shellescape(Curl()) .. ' -K -', join(config, "\n") .. "\n")
  if v:shell_error != 0
    throw 'jira: curl failed (exit ' .. v:shell_error .. '): '
      .. substitute(trim(output), '\n', ' ', 'g')
  endif

  var res = ParseOutput(output)
  try
    res.json = empty(res.body) ? {} : json_decode(res.body)
  catch
    res.json = {}
  endtry
  return res
enddef

# Like Request(), but returns the decoded JSON and throws on a non-2xx
# status with Jira's error message.
export def Api(method: string, path: string, body: string = ''): any
  const res = Request(method, path, body)
  if res.status < 200 || res.status >= 300
    throw 'jira: HTTP ' .. res.status .. ': ' .. ErrorMessage(res)
  endif
  return res.json
enddef

# Web URL of an issue.
export def BrowseUrl(key: string): string
  return Url() .. '/browse/' .. key
enddef

# Extracts a readable error message from a Jira error response.
def ErrorMessage(res: dict<any>): string
  const json = res.json
  if type(json) == v:t_dict
    const msgs = get(json, 'errorMessages', [])
    if !empty(msgs)
      return join(msgs, '; ')
    endif
    if has_key(json, 'message')
      return json.message
    endif
  endif
  if res.status == 401
    return 'check the account email and API token'
  endif
  return strcharpart(trim(res.body), 0, 200)
enddef

# ----------------------------------------------------------------------------
# Login

# Asks for missing settings. Returns false if the user cancelled.
export def EnsureCredentials(): bool
  if empty(Url())
    const url = input('Jira URL (https://<site>.atlassian.net): ')
    if empty(url)
      return false
    endif
    g:jira_url = url
  endif
  if empty(User())
    session_user = input('Jira account email: ')
    if empty(session_user)
      return false
    endif
  endif
  if empty(Token().token)
    session_token = inputsecret('Jira API token: ')
    if empty(session_token)
      return false
    endif
  endif
  return true
enddef

# Verifies the credentials with GET /rest/api/3/myself and remembers the
# user on success. Returns the user dict; throws on failure.
export def Authenticate(): dict<any>
  current_user = {}
  const res = Request('GET', '/rest/api/3/myself')
  if res.status != 200
    const source = Token().source
    if res.status == 401 && source == 'session'
      session_token = ''
    endif
    throw 'jira: login failed (HTTP ' .. res.status .. '): ' .. ErrorMessage(res)
  endif
  current_user = res.json
  return current_user
enddef

# :JiraLogin
export def Login()
  if !EnsureCredentials()
    redraw
    echo 'jira: login cancelled'
    return
  endif
  redraw
  try
    const me = Authenticate()
    echomsg 'jira: logged in as ' .. get(me, 'displayName', '?')
      .. ' <' .. get(me, 'emailAddress', User()) .. '>'
      .. (Token().source == 'env' ? ' (token from $' .. TokenEnv() .. ')' : '')
  catch /^jira:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
enddef

# :JiraLogout - forget the session token, typed email and current user.
# A token from the environment variable is not affected.
export def Logout()
  session_token = ''
  session_user = ''
  current_user = {}
  echomsg 'jira: logged out'
    .. (Token().source == 'env'
      ? ' ($' .. TokenEnv() .. ' is still set and will be used)' : '')
enddef

# ----------------------------------------------------------------------------
# Environment check

# Collects an environment report. Returns the lines and the number of
# problems found, so it can be tested without inspecting messages.
# Makes no network request.
export def CheckReport(): dict<any>
  var lines: list<string> = []
  var errors = 0

  add(lines, 'jira.vim ' .. VERSION)
  add(lines, 'Vim:      ' .. v:version / 100 .. '.' .. v:version % 100
    .. (has('patch-9.0.0000') ? '' : '  [ERROR] Vim 9.0+ required'))
  add(lines, 'Platform: ' .. Platform()
    .. (Platform() == 'msys' ? ' (' .. $MSYSTEM .. ')' : ''))

  const curl = Curl()
  const path = exepath(curl)
  if empty(path)
    errors += 1
    add(lines, 'curl:     [ERROR] "' .. curl .. '" not found in $PATH'
      .. ' (set g:jira_curl)')
  else
    add(lines, 'curl:     ' .. path)
  endif

  const url = Url()
  add(lines, 'URL:      ' .. (empty(url) ? '(not set)' : url)
    .. (!empty(url) && url !~? '^https://' ? '  [WARN] should start with https://' : ''))
  const user = User()
  add(lines, 'User:     ' .. (empty(user) ? '(not set)' : user))
  const source = Token().source
  add(lines, 'Token:    ' .. (source == 'env' ? 'from $' .. TokenEnv()
    : source == 'session' ? 'typed (this session only)' : '(not set)'))
  add(lines, 'Login:    ' .. (empty(current_user) ? 'not logged in'
    : get(current_user, 'displayName', '?')))

  add(lines, errors == 0 ? 'OK' : errors .. ' problem(s) found')
  return {lines: lines, errors: errors}
enddef

# :JiraCheck - show the environment report.
export def Check()
  const report = CheckReport()
  for line in report.lines
    if line =~ '\[ERROR\]'
      echohl ErrorMsg
      echomsg line
      echohl None
    elseif line =~ '\[WARN\]'
      echohl WarningMsg
      echomsg line
      echohl None
    else
      echomsg line
    endif
  endfor
enddef
