if &cp || exists('autoloaded_projectroot')
  finish
endif
let autoloaded_projectroot = 1

" Options {{{1
if !exists('g:rootmarkers')
  let g:rootmarkers = ['.projectroot', '.git', '.hg', '.svn', '.bzr', '_darcs', 'build.xml']
endif
if !exists('g:projectroot_nested_git_submodule')
  let g:projectroot_nested_git_submodule = 0
endif

" projectroot#get([file]): get the project root (if any) {{{1
function! projectroot#get(...)
  let fullfile = s:getfullname(a:0 ? a:1 : '')
  if exists('b:projectroot')
    if stridx(fullfile, fnamemodify(b:projectroot, ':p'))==0
      return b:projectroot
    endif
  endif
  if fullfile =~ '^fugitive:/'
    if exists('b:git_dir')
      return fnamemodify(b:git_dir, ':h')
    endif
    return '' " skip any fugitive buffers early
  endif
  for marker in g:rootmarkers
    let pivot=fullfile
    while 1
      let prev=pivot
      let pivot=fnamemodify(pivot, ':h')
      let fn = pivot.(pivot == '/' ? '' : '/').marker

      if marker == '.git'
        let result=s:examinedotgit(fn)
        if result == 3
          " if the .git file indicates this git repo is actually a submodule
          " contained inside a parent repo, then keep recursing up the
          " directory structure
          continue
        elseif result > 0
          " if .git is a file or directory, it is our project root marker
          return pivot
        endif
      elseif filereadable(fn) || isdirectory(fn)
        return pivot
      endif
      if pivot==prev
        break
      endif
    endwhile
  endfor
  return ''
endfunction

" projectroot#guess([file]): guesses and returns the project root {{{1
function! projectroot#guess(...)
  let projroot = projectroot#get(a:0 ? a:1 : '')
  if len(projroot)
    return projroot
  endif
  " Not found: return parent directory of current file / file itself.
  let fullfile = s:getfullname(a:0 ? a:1 : '')
  return !isdirectory(fullfile) ? fnamemodify(fullfile, ':h') : fullfile
endfunction

" projectroot#cd([file]): changes directory to the project of the given file {{{1
" Args: 0: (optional) filename
"       1: (optional) command (Default: "cd")
function! projectroot#cd(...)
  let root = projectroot#guess(get(a:000, 0, ''))
  let cdcmd = get(a:000, 1, 'cd')
  exe cdcmd fnameescape(root)
endfunction

" projectroot#exe(cmd): executes cmd from within the project directory {{{1
function! projectroot#exe(args)
  let olddir = getcwd()
  try
    ProjectRootCD
    exe join(a:args)
  finally
    exe 'cd' fnameescape(olddir)
  endtry
endfunction

" projectroot#buffers([file]): returns all buffers from the same project {{{1
function! projectroot#buffers(...)
  let root = projectroot#guess(s:getfullname(a:0 ? a:1 : ''))
  let bufs = map(s:getallbuffers(), 'fnamemodify(bufname(v:val),":p")')
  let bufs = filter(bufs, 'stridx(v:val,root)==0 && filereadable(v:val)')
  return sort(bufs)
endfunction

" projectroot#bufdo(cmd, bang): execute the given command for all project buffers {{{1
function! projectroot#bufdo(args, bang)
  let cmd=join(a:args)
  let bang=len(a:bang) ? '!':''
  let ei=&ei
  set ei+=Syntax
  try
    for f in projectroot#buffers()
      exe 'b'.bang f
      exe cmd
    endfor
  finally
    let &ei=ei
  endtry
endfunction

" projectroot#bufnext(count, [file]): returns the next buffer in the project {{{1
function! projectroot#bufnext(count, ...)
  let thisbuf = s:getfullname(a:0 ? a:1 : '')
  let l = projectroot#buffers(thisbuf)

  if !exists('g:projectroot_noskipbufs')
    let l=filter(l, 'bufwinnr(v:val)==-1 || v:val==thisbuf')
  endif

  let i = index(l, thisbuf)
  let i = i>=0 ? i : 0
  let s = len(l)
  let target = (((i+a:count) % s)+s) % s
  return bufnr(get(l, target, thisbuf))
endfunction

" Utility methods {{{1
function! s:getallbuffers()
  redir => m
  sil exe ':ls'
  redir END
  return map(split(m,'\n'), 'matchstr(v:val,''\v\d+'')*1')
endfunction

function! s:getfullname(f)
  let f = a:f
  let f = f=~"'." ? s:getmarkfile(f[1]) : f
  let f = len(f) ? f : expand('%')
  return fnamemodify(f, ':p')
endfunction

function! s:getmarkfile(mark)
  try
    redir => m
    sil exe ':marks' a:mark
    redir END
    let f = split(split(m,'\n')[-1])[-1]
    return filereadable(f) ? f : ''
  catch
    return ''
  endtry
endfunction

function! s:examinedotgit(fn)
  " returns one of:
  " 0: The .git file at a:fn doesn't exist.
  " 1: The .git file at a:fn is a directory.
  " 2: The .git file at a:fn is a regular file.
  " 3: The .git file at a:fn is a nested git submodule (Only when
  "    g:projectroot_nested_git_submodule is set).
  if isdirectory(a:fn)
    return 1  " a directory
  endif

  if g:projectroot_nested_git_submodule && exists('*readfile')
    " check to see if we're in a .git submodule
    try
      let lines=readfile(a:fn, 0, 1)
    catch /E484/
      return 0  " doesn't exist
    endtry
    if len(lines) && lines[0] =~ '^gitdir: \%(\.\./\)\+\.git/modules/'
      return 3  " the .git is a nested git submodule
    endif

    return 2  " the .git is some other type of .git file (probably a worktree)
  endif

  " g:projectroot_nested_git_submodule wasn't set - just check to see if the
  " .git entry is a plain file
  if filereadable(a:fn)
    return 2  " the .git is some other type of .git file (probably a worktree)
  endif

  return  0  " doesn't exist
endfun

