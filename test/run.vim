vim9script
# Minimal test runner. Usage (from the repo root):
#   vim -Nu NONE -i NONE -es -S test/run.vim
# Exits with status 0 if all tests pass, 1 otherwise.

const root = fnamemodify(expand('<sfile>:p'), ':h:h')
&runtimepath = root .. ',' .. &runtimepath
filetype plugin on
execute 'source ' .. fnameescape(root .. '/plugin/jira.vim')

var output: list<string> = []
var failed = 0

for file in glob(root .. '/test/test_*.vim', true, true)
  execute 'source ' .. fnameescape(file)
endfor

for name in getcompletion('Test_', 'function')
  const fname = substitute(name, '()$', '', '')
  v:errors = []
  try
    call(fname, [])
  catch
    add(v:errors, 'Exception: ' .. v:exception .. ' @ ' .. v:throwpoint)
  endtry
  if empty(v:errors)
    add(output, 'PASS ' .. fname)
  else
    failed += 1
    add(output, 'FAIL ' .. fname)
    output->extend(v:errors->mapnew((_, e) => '    ' .. e))
  endif
endfor

add(output, failed == 0 ? 'All tests passed.' : failed .. ' test(s) failed.')
# Tests may leave read-only buffers behind; print from a fresh one.
silent! only!
enew!
setlocal modifiable
# In silent Ex mode (-es) :print writes to stdout on every platform.
setline(1, output)
:%print
execute failed == 0 ? 'qall!' : 'cquit!'
