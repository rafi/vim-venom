# Vim Venom

> Activates your Python virtual-environments while working in Neo/Vim.

<!-- vim-markdown-toc GFM -->

* [Features](#features)
* [Install](#install)
* [Configuration](#configuration)
* [Functions & Commands](#functions--commands)
* [Python Runtime Selection](#python-runtime-selection)
* [Virtual-Environment Detection](#virtual-environment-detection)
  * [External Tools Integration](#external-tools-integration)
* [User Events](#user-events)
* [Caveats](#caveats)
* [Copyright](#copyright)

<!-- vim-markdown-toc -->

## Features

* Select python runtime for current project
* Detect your project's virtualenv path via placeholders (e.g. `.venv`)
* Detect virtualenv via popular tools: [pipenv], [poetry], etc.
* User Vim events on de/activation

## Install

Ensure your neo/vim instance supports `python3`, i.e. `:echo has('python3')`
should print `1`.  Use your favorite plugin-manager, for example [dein.vim]:

```viml
call dein#add('rafi/vim-venom', { 'on_ft': 'python' })
```

Or, if you're using [vim-plug], I got your back too:

```viml
Plug 'rafi/vim-venom', { 'for': 'python' }
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `g:venom_auto_activate` | Automatically tries to detect and activate virtualenv | `1`
| `g:venom_use_tools` | Use external-tools to detect virtualenv | `1`
| `g:venom_echo` | Upon activation show friendly message | `1`
| `g:venom_quiet` | Be quiet when failing to find environments | `0`
| `g:venom_symbol` | Icon for statusline helper function | `🐍`
| `g:venom_tools` | External-tools configuration | See [here](#external-tools-integration)

## Functions & Commands

* `:VenomActivate [path]` / `venom#activate([path])`
  - Without argument: Try to detect virtual-environment
  - With argument: Find python runtime in path and place a marker to persist
    selection.
* `:VenomDeactivate` / `venom#deactivate()`
* `venom#statusline()`

## Python Runtime Selection

User can activate a different Python runtime, and use auto-completion when
selecting one, using `:VenomActivate` and <kbd>Tab</kbd>.

:warning: Only tested with **Neovim**.

## Virtual-Environment Detection

Once activation runs manually (without arguments) or automatically when
`g:venom_auto_activate` is enabled, plugin will attempt to detect the project's
virtual-environment path using several strategies:

1. Detect `.venv/` directory in project's directory.
1. Detect `.venv` file containing environment path in plain-text.
1. Detect with external-tools (if `g:venom_use_tools` is enabled).

See the following `g:venom_tools` for external tools usage & support.

### External Tools Integration

Enabling `g:venom_use_tools` leverages external tools in-order to resolve
the project's virtual-environment path, plugin currently supports:

* [poetry]
* [pipenv]

You can extend and change the usage. These are the default values:

```viml
let g:venom_use_tools = 1
let g:venom_tools = {
  \ 'poetry': 'poetry env info -p',
  \ 'pipenv': 'pipenv --venv'
  \ }
```

## User Events

As a user, you have two events you can hook triggers to extend behavior:

* `VenomActivated`
* `VenomDeactivated`

For example, if you use [deoplete] and [deoplete-jedi] together:

```viml
" Deoplete Jedi: Set python executable from PATH
autocmd User VenomActivated,VenomDeactivated
  \ let g:deoplete#sources#jedi#python_path =
  \   exepath('python' . (has('win32') ? '.exe' : ''))
```

Or use [jedi-vim]'s new `:JediUseEnvironment` feature (pending [#836](https://github.com/davidhalter/jedi-vim/pull/836)):

```viml
" Jedi: Set environment from PATH
autocmd User VenomActivated,VenomDeactivated
  \ silent! execute 'JediUseEnvironment ' .
  \   exepath('python' . (has('win32') ? '.exe' : ''))
```

## Caveats

* By default, `FileType python` event triggers plugin activation. You can add
  other events yourself, e.g.: `autocmd BufWinEnter *.py call venom#activate()`
* Plugin doesn't alter Neovim's `g:python3_host_prog`. I don't think if it
  should.
* Mostly tested with Neovim

## Copyright

© 2020 Rafael Bodill

[vim-plug]: https://github.com/junegunn/vim-plug
[dein.vim]: https://github.com/shougo/dein.vim
[pyenv]: https://github.com/pyenv/pyenv
[poetry]: https://github.com/python-poetry/poetry
[pipenv]: https://github.com/pypa/pipenv
[deoplete]: https://github.com/Shougo/deoplete.nvim
[deoplete-jedi]: https://github.com/deoplete-plugins/deoplete-jedi
[jedi-vim]: https://github.com/davidhalter/jedi-vim
