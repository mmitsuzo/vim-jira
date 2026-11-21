vim9script
# Shared test helpers. Imported by test_*.vim with:  import './helper.vim'

# Like assert_fails(), but uses try/catch: assert_fails() makes Vim exit
# with status 1 in -es mode even when the assertion passes.
export def AssertThrows(F: func, pattern: string)
  try
    F()
    assert_report('expected exception matching: ' .. pattern)
  catch
    assert_match('\V' .. escape(pattern, '\'), v:exception)
  endtry
enddef

export def ClearCredentials()
  unlet! g:jira_url g:jira_user g:jira_token_env g:jira_curl
  for name in ['JIRA_URL', 'JIRA_USER', 'JIRA_API_TOKEN', 'MY_TOKEN']
    setenv(name, null)
  endfor
  silent JiraLogout
enddef

# The fake curl is a shell script, so it needs a Unix-like shell
# (Linux, macOS, Git-Bash, Cygwin).
export def HasShell(): bool
  return has('unix') || has('win32unix')
enddef

var fake_dir = ''

# Installs a fake curl as g:jira_curl together with valid credentials.
# Call N saves the config it receives on stdin to <dir>/config.N (and
# <dir>/config) and prints <dir>/body.N if it exists, else <dir>/body,
# followed by the status. Returns the directory.
export def SetupFakeCurl(): string
  ClearCredentials()
  fake_dir = tempname()
  mkdir(fake_dir, 'p')
  const script = fake_dir .. '/fake-curl'
  writefile([
    '#!/bin/sh',
    'd=$(dirname "$0")',
    'n=$(( $(cat "$d/count" 2>/dev/null || echo 0) + 1 ))',
    'echo $n > "$d/count"',
    'cat > "$d/config.$n"',
    'cp "$d/config.$n" "$d/config"',
    'f="$d/body"; [ -f "$d/body.$n" ] && f="$d/body.$n"',
    'printf "%s\n%s" "$(cat "$f")" "$(cat "$d/status")"',
  ], script)
  setfperm(script, 'rwxr-xr-x')
  g:jira_curl = script
  g:jira_url = 'https://x.atlassian.net/'
  g:jira_user = 'a@example.com'
  setenv('JIRA_API_TOKEN', 'envtoken')
  Respond('')
  return fake_dir
enddef

def Encode(body: any): string
  return type(body) == v:t_string ? body : json_encode(body)
enddef

# Every following request gets this response.
export def Respond(body: any, status: number = 200)
  RespondSequence([])
  writefile([Encode(body)], fake_dir .. '/body')
  writefile([string(status)], fake_dir .. '/status')
enddef

# The next requests get these bodies in order (status 200), then the
# response set with Respond().
export def RespondSequence(bodies: list<any>)
  delete(fake_dir .. '/count')
  for f in glob(fake_dir .. '/body.*', true, true)
    delete(f)
  endfor
  for i in range(len(bodies))
    writefile([Encode(bodies[i])], fake_dir .. '/body.' .. (i + 1))
  endfor
  writefile(['200'], fake_dir .. '/status')
enddef

# Lines of the curl config sent by the last request (or by request n).
export def LastConfig(dir: string, n: number = 0): list<string>
  return readfile(dir .. '/config' .. (n > 0 ? '.' .. n : ''))
enddef

# Number of requests since the last Respond()/RespondSequence().
export def RequestCount(dir: string): number
  return filereadable(dir .. '/count') ? str2nr(readfile(dir .. '/count')[0]) : 0
enddef

export def TeardownFakeCurl(dir: string)
  delete(dir, 'rf')
  fake_dir = ''
  ClearCredentials()
enddef
