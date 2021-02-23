" vim-venom
" ---
" See: https://github.com/rafi/vim-venom

python3 import vim, sys

let s:script_dir = fnamemodify(resolve(expand('<sfile>:p')), ':h')

" Find project virtual-environment and activate it
function! venom#activate(...) abort
	if &previewwindow == 1
	  return
	endif

	" Get current file info
	let l:bufname = bufname('%')
	let l:virtual_env = getbufvar(l:bufname, 'virtual_env')

	" Use python executable from user argument
	if a:0 > 0 && ! empty(a:1)
		let l:virtual_env = s:parse_runtime(a:1)
		if empty(l:virtual_env)
			call s:echo('error', printf("Unable to find python executable at '%s'",
				\ fnamemodify(a:1, ':~')))
			return
		endif
		" Persist selection using a plain-text file with runtime's path
		call s:persist_runtime(l:virtual_env)

	elseif empty(l:virtual_env)
		" Find virtual-environment within paths, or using tools
		let [l:virtual_env, l:log] = s:find_virtualenv(expand('%:p:h'))
		if empty(l:virtual_env) || fnamemodify(l:virtual_env, ':t') ==# '.git'
			call setbufvar(l:bufname, 'virtual_env', '-')
			if ! g:venom_quiet
				call extend(l:log, ['>',
					\ 'Unable to find project''s virtual environment.'
					\ . ' Run :messages to view debug information.'])
				call s:echo('info', l:log)
			endif
			return
		endif
	endif

	" Abort buffers that no environments were found for
	if l:virtual_env == '-'
		return
	endif

	" Check if a venv is currently active and match with what we found
	if len($VIRTUAL_ENV) > 0
		if l:virtual_env ==# $VIRTUAL_ENV
			return
		endif
		" Deactivate current venv before activating the new found one
		call venom#deactivate()
	endif

	" Activate virtual-environment
	" Execute activate_this.py from virtual-environment if one exists,
	" otherwise execute the included script as if it's in the venv's path.
	let s:original_path = $PATH
	let s:original_syspath = py3eval('sys.path')
	try
		let l:bin_dir = has('win32') ? '/Scripts' : '/bin'
		let l:activator = '/activate_this.py'
		let l:activate_path = l:virtual_env . l:bin_dir . l:activator
		let l:activate_src = filereadable(l:activate_path)
			\ ? l:activate_path : s:script_dir . l:activator

		python3 with open(vim.eval('l:activate_src')) as handler:
			\ exec(handler.read(), {'__file__': vim.eval('l:activate_path')})

		" Set vim env variables
		let $PATH = l:virtual_env . l:bin_dir . ':' . $PATH
		let $VIRTUAL_ENV = l:virtual_env
		call setbufvar(l:bufname, 'virtual_env', l:virtual_env)
	catch /^.*/
		call s:echo('error',
			\ printf('Error while trying to activate environment "%s": %s',
			\ fnamemodify(l:virtual_env, ':t'), v:exception))
		return
	endtry

	" Run the user callback for activation
	silent doautocmd User VenomActivated

	if g:venom_echo
		call s:echo('info', printf('Activated environment "%s" %s',
			\ fnamemodify(l:virtual_env, ':t'), fnamemodify(l:virtual_env, ':~')))
	endif
endfunction

" Deactivate current virtual-environment
function! venom#deactivate() abort
	try
		" Clean variables
		let l:virtual_env = $VIRTUAL_ENV
		call setbufvar('%', 'virtual_env', '')
		unlet $VIRTUAL_ENV

		" Restore env PATH
		if exists('s:original_path') && ! empty(s:original_path)
			let $PATH = s:original_path
			unlet s:original_path
		endif

		" Restore python's sys.path
		if exists('s:original_syspath') && ! empty(s:original_syspath)
			python3 sys.path[:] = vim.eval('s:original_syspath')
			unlet s:original_syspath
		endif
	catch /^.*/
		call s:echo('error',
			\ printf('Error while trying to deactivate environment "%s": %s',
			\ fnamemodify(l:virtual_env, ':t'), v:exception))
		return
	endtry

	" Run the user callback for deactivation
	silent doautocmd User VenomDeactivated

	if g:venom_echo
		call s:echo('info', printf('Deactivated environment "%s" %s',
			\ fnamemodify(l:virtual_env, ':t'), fnamemodify(l:virtual_env, ':~')))
	endif
endfunction

function! venom#find_python_runtimes(lead, line, cursor) abort
	let l:runtimes = []
	if has('win32')
		" TODO
	else
		call extend(l:runtimes, split(system('which -a python python3'), "\n"))
	endif
	" Find venvs under pyenv root, if installed
	if executable('pyenv')
		let l:pyenv_root = trim(system('pyenv root'))
		let l:versions = globpath(l:pyenv_root, 'versions/*/bin/python', 0, 1)
		call extend(l:runtimes, l:versions)
	endif
	return l:runtimes
endfunction

" Simple display of current activated virtual-env
function! venom#statusline() abort
	let l:virtual_env = expand('$VIRTUAL_ENV')

	if ! empty(l:virtual_env)
		return trim(fnamemodify(l:virtual_env, ':t') . ' ' . g:venom_symbol)
	endif
	return ''
endfunction

" Finds project's virtual-environment path
function! s:find_virtualenv(dir) abort
	" Try to find certain directory names or placeholder text files that
	" are probably the virtual-environment we're looking for.
	let l:log = ['Searching within parents for ' . string(g:venom_root_markers)]
	let l:path = s:find_parents(a:dir, g:venom_root_markers)
	if ! empty(l:path)
		if isdirectory(l:path)
			return [l:path, l:log]
		elseif filereadable(l:path)
			" Read location of virtual-environment from text-file
			let l:path = get(readfile(l:path, '', 1), 0)
			if ! empty(l:path)
				if isdirectory(l:path)
					return [l:path, l:log]
				endif
				let l:workon_path = expand('$WORKON_HOME') . '/' . l:path
				if isdirectory(l:workon_path)
					return [l:workon_path, l:log]
				endif
			endif
		endif
	endif

	" Use predefined executables to find virtualenv's location.
	let l:path = ''
	if g:venom_use_tools
		call add(l:log, 'Searching with external executables')
		for l:binary in keys(g:venom_tools)
			if ! executable(l:binary)
				continue
			endif
			let l:result = trim(system(g:venom_tools[l:binary]))
			call extend(l:log, ['$ ' . g:venom_tools[l:binary], l:result])
			if v:shell_error == 0 && ! empty(l:result)
				let l:lines = split(l:result, '\n')
				if len(l:lines) == 1
					let l:path = matchstr(l:lines[0], '\zs/\S*')
				else
					call s:echo('error', printf('Erroneous shell output from "%s" %s',
						\ l:binary, l:result))
				endif
			endif
		endfor
	endif

	return [l:path, l:log]
endfunction

" Parses, validates and returns python runtime prefix directory
function! s:parse_runtime(runtime_path) abort
	let l:runtime_dir = ''
	let l:python_executable = trim(a:runtime_path)
	if isdirectory(l:python_executable)
		let l:bin = has('win32') ? '/Scripts/python.exe' : '/bin/python'
		let l:python_executable .= l:bin
	endif

	" Python executable is valid, use it
	if executable(l:python_executable)
		let l:runtime_dir = fnamemodify(l:python_executable, ':h:h')
	endif
	return l:runtime_dir
endfunction

" Persist user's python runtime selection in a plain-text marker file
function! s:persist_runtime(runtime_prefix) abort
	" Find project root and persist selected runtime with .venv marker
	let l:project_root = s:find_parents(getcwd(), g:venom_root_markers)
	if ! empty(l:project_root)
		let l:venv_marker = fnamemodify(l:project_root, ':h') . '/.venv'
		if isdirectory(l:venv_marker) || filereadable(l:venv_marker)
			call s:echo('info',
				\ printf("Runtime marker file already exists at '%s', skip overwrite",
				\ fnamemodify(l:venv_marker, ':~')))
		else
			call writefile([a:runtime_prefix], l:venv_marker)
			if ! g:venom_quiet
				call s:echo('info',
					\ printf("Persist Python runtime with placeholder at '%s'",
					\ fnamemodify(l:venv_marker, ':~')))
			endif
		endif
	endif
endfunction

" Finds files or directories in parents of current directory
function! s:find_parents(dir, patterns) abort
	let l:path = ''
	for l:pattern in a:patterns
		let l:is_dir = stridx(l:pattern, '/') != -1
		let l:match = l:is_dir ? finddir(l:pattern, a:dir . ';')
			\ : findfile(l:pattern, a:dir . ';')
		if ! empty(l:match)
			let l:path = fnamemodify(l:match, l:is_dir ? ':p:h' : ':p')
			break
		endif
	endfor
	return l:path
endfunction

" Asynchronous echomsg
function! s:echo(type, msg) abort
	let l:types = { 'info': 'Identifier', 'error': 'ErrorMsg' }
	call timer_start(10, function('s:_echo', [l:types[a:type], a:msg]))
endfunction

" Asynchronous echomsg function callback
function! s:_echo(highlight, msg, timer) abort
	let l:msgs = type(a:msg) == type('') ? [a:msg] : a:msg
	execute('echohl ' . a:highlight)
	for l:msg in l:msgs
		echomsg '[venom] ' . l:msg
	endfor
	echohl None
endfunction

" vim: set ts=2 sw=2 tw=80 noet :
