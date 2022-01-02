" vim-venom
" ---
" See: https://github.com/rafi/vim-venom

" Check loaded state
if exists('g:venom_loaded')
	finish
endif
let g:venom_loaded = 1

" Verify python 3 feature support
if ! has('python3')
	echohl ErrorMsg
	echomsg 'Python3 is needed for vim-venom to work.'
	echohl None
	finish
endif

" Auto-activate virtualenv on Python files?
if ! exists('g:venom_auto_activate')
	let g:venom_auto_activate = 1
endif

" Upon de/activation, echo a message?
if ! exists('g:venom_echo')
	let g:venom_echo = 1
endif

" Silence warnings and information output
if ! exists('g:venom_quiet')
	let g:venom_quiet = 0
endif

" Icon for status-line function
if ! exists('g:venom_symbol')
	let g:venom_symbol = '🐍'
endif

" Project root markers
if ! exists('g:venom_root_markers')
	let g:venom_root_markers = ['.venv', '.venv/', '.python-version', '.git/']
endif

" Detect virtualenv with external tools? (e.g. poetry, pipenv)
if ! exists('g:venom_use_tools')
	let g:venom_use_tools = 1
endif

" External tools configuration
if ! exists('g:venom_tools')
	let g:venom_tools = {
		\ 'poetry': 'poetry env info -p',
		\ 'pipenv': 'pipenv --venv'
		\ }
endif

" Commands
command! -nargs=? -complete=customlist,venom#find_python_runtimes
	\ VenomActivate call venom#activate(<q-args>)

command! VenomDeactivate call venom#deactivate()

" Auto-activate environment activation
if g:venom_auto_activate == 1
	augroup venom_plugin
		autocmd!
		autocmd FileType python call venom#activate()
	augroup END
endif

" vim: set ts=2 sw=2 tw=80 noet :
