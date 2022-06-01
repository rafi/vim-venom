-- vim-venom
--
-- See: https://github.com/rafi/vim-venom
-- Many functions taken from nvim-lspconfig/util.lua

local validate = vim.validate
local uv = vim.loop

local default_config = {
	auto_activate = true,
	echo = true,
	quiet = false,
	symbol = '🐍',
	root_patterns = { '.venv', '.python-version' },
	use_tools = true,
	tools = {
		poetry = 'poetry env info -p',
		pipenv = 'pipenv --venv',
	},
}

local original_path = ''
-- local original_syspath = ''
local unresolved_paths = {}
local pyenv_root = os.getenv('PYENV_ROOT')
local workon_home = os.getenv('WORKON_HOME')

-- File and path utilies taken from nvim-lspconfig.
local M = {}
M.config = default_config
M.path = (function()
	local is_windows = uv.os_uname().version:match('Windows')
	local path_sep = is_windows and '\\' or '/'

	local function exists(filename)
		local stat = uv.fs_stat(filename)
		return stat and stat.type or false
	end

	local function is_dir(filename)
		return exists(filename) == 'directory'
	end

	local function is_file(filename)
		return exists(filename) == 'file'
	end

	local function is_fs_root(path)
		if is_windows then
			return path:match('^%a:$')
		else
			return path == '/'
		end
	end

	local function is_absolute(filename)
		if is_windows then
			return filename:match('^%a:') or filename:match('^\\\\')
		else
			return filename:match('^/')
		end
	end

	local function basename(path)
		return string.gsub(path, '(.*/)(.*)', '%2')
	end

	local function dirname(path)
		local strip_dir_pat = '/([^/]+)$'
		local strip_sep_pat = '/$'
		if not path or #path == 0 then
			return
		end
		local result = path:gsub(strip_sep_pat, ''):gsub(strip_dir_pat, '')
		if #result == 0 then
			if is_windows then
				return path:sub(1, 2):upper()
			else
				return '/'
			end
		end
		return result
	end

	local function path_join(...)
		local result = table.concat(vim.tbl_flatten({ ... }), path_sep):gsub(path_sep .. '+', path_sep)
		return result
	end

	-- Iterate the path until we find the rootdir.
	local function iterate_parents(path)
		local function it(_, v)
			if v and not is_fs_root(v) then
				v = dirname(v)
			else
				return
			end
			if v and uv.fs_realpath(v) then
				return v, path
			else
				return
			end
		end
		return it, path, path
	end

	return {
		is_dir = is_dir,
		is_file = is_file,
		is_absolute = is_absolute,
		is_windows = is_windows,
		basename = basename,
		dirname = dirname,
		join = path_join,
		path_sep = path_sep,
		exists = exists,
		iterate_parents = iterate_parents,
	}
end)()

-- Taken from nvim-lspconfig.
function M.search_ancestors(startpath, func)
	validate({ func = { func, 'f' } })
	local found = func(startpath)
	if found then
		return found
	end
	local guard = 100
	for path in M.path.iterate_parents(startpath) do
		-- Prevent infinite recursion if our algorithm breaks
		guard = guard - 1
		if guard == 0 then
			return
		end

		found = func(path)
		if found then
			return found
		end
	end
end

-- Taken from nvim-lspconfig.
function M.find_pattern(...)
	local patterns = vim.tbl_flatten({ ... })
	local function matcher(path)
		for _, pattern in ipairs(patterns) do
			local path_joined = M.path.join(path, pattern)
			for _, p in ipairs(vim.fn.glob(path_joined, true, true)) do
				if M.path.exists(p) then
					return p
				end
			end
		end
	end
	return function(startpath)
		return M.search_ancestors(startpath, matcher)
	end
end

function M.split(s, delimiter)
	local result = {}
	for match in (s .. delimiter):gmatch('(.-)' .. delimiter) do
		if match ~= '' then
			table.insert(result, match)
		end
	end
	return result
end

-- Finds project's virtual-environment path
function M.find_virtualenv()
	-- Try to find certain directory names or placeholder text files that
	-- are probably the virtual-environment we're looking for.
	local found_path = M.find_pattern(unpack(M.config.root_patterns))(vim.fn.getcwd())
	if not (found_path == nil or found_path == '') then
		if M.path.is_dir(found_path) then
			return found_path
		elseif M.path.is_file(found_path) then
			-- Read location of virtual-environment from text-file
			local file = io.open(found_path)
			local user_dir = file:read('*l')
			file:close()

			if not (user_dir == nil or user_dir == '') then
				-- Use file contents as an absolute path
				if M.path.is_absolute(user_dir) and M.path.is_dir(user_dir) then
					return user_dir
				end

				-- Use file contents as a pyenv version
				local pyenv_version = M.path.join(pyenv_root, 'versions', user_dir)
				if pyenv_version ~= '' and M.path.is_dir(pyenv_version) then
					return pyenv_version
				end

				-- Use file contents as a virtualenvwrapper directory
				local workon_dir = M.path.join(workon_home, user_dir)
				if workon_dir ~= '' and M.path.is_dir(workon_dir) then
					return workon_dir
				end
			end
		end
	end

	-- Use predefined executables to find virtualenv's location.
	if M.config.use_tools then
		for tool, cmd in pairs(M.config.tools) do
			M.echo('info', string.format('%s', cmd))
			if vim.api.nvim_eval(string.format("executable('%s')", tool)) then
				local handle = io.popen(cmd)
				local result = handle:read('*a')
				handle:close()

				local lines = M.split(result, '\n')
				if table.getn(lines) == 1 then
					return lines[1]
				else
					M.echo('error', string.format('Erroneous shell output from %s %s', tool, result))
				end
			end
		end
	end

	return ''
end

-- Find project virtual-environment and activate it
function M.activate()
	-- Ensure window has a real file.
	if vim.wo.previewwindow or vim.wo.diff then
		return false
	end

	-- Get current file info
	local bufnr = vim.api.nvim_get_current_buf()
	local virtual_env = vim.b.virtual_env or ''

	-- TODO: Use python executable from user argument

	-- Detect and activate Python virtualenv
	if virtual_env == '' then
		-- Abort early if this path couldn't be resolved previously.
		local file_dir = M.path.dirname(vim.api.nvim_buf_get_name(bufnr))
		for _, v in pairs(unresolved_paths) do
			if file_dir == v then
				return false
			end
		end
		-- Find virtual-environment within paths, or using tools
		virtual_env = M.find_virtualenv()
		if virtual_env == nil or virtual_env == '' then
			vim.api.nvim_buf_set_var(bufnr, 'virtual_env', '-')
			table.insert(unresolved_paths, file_dir)
			if not M.config.quiet then
				print("Unable to find project's virtual environment." .. ' Run :messages to view debug information.')
			end
			return false
		end
	end

	-- Abort buffers that no environments were found for
	if virtual_env == '-' then
		return false
	end

	-- Check if a venv is currently active and match with what we found
	local global_virtual_env = os.getenv('VIRTUAL_ENV') or ''
	if global_virtual_env ~= '' then
		if virtual_env == global_virtual_env then
			return false
		end
		-- Deactivate current venv before activating the new found one
		M.deactivate()
	end

	-- Activate virtual-environment
	original_path = os.getenv('PATH')
	-- INFO: Doesn't change python's sys.path.
	-- original_syspath = vim.fn.py3eval('sys.path')

	local bin_path = M.path.join(virtual_env, M.path.is_windows and 'Scripts' or 'bin')

	vim.fn.setenv('VIRTUAL_ENV', virtual_env)
	vim.fn.setenv('PATH', bin_path .. ':' .. os.getenv('PATH'))
	vim.api.nvim_buf_set_var(bufnr, 'virtual_env', virtual_env)

	if M.config.echo then
		M.echo('info', string.format('Activated environment "%s" %s', M.path.basename(virtual_env), virtual_env))
	end
end

-- Deactivate current virtual-environment
function M.deactivate()
	local bufnr = vim.api.nvim_get_current_buf()
	local virtual_env = os.getenv('VIRTUAL_ENV') or ''

	-- Clean variables
	vim.api.nvim_buf_del_var(bufnr, 'virtual_env')
	vim.fn.setenv('VIRTUAL_ENV', nil)

	-- Restore env PATH
	if original_path ~= '' then
		vim.fn.setenv('PATH', original_path)
		original_path = ''
	end

	-- INFO: Doesn't change python's sys.path.

	if M.config.echo then
		M.echo('info', string.format('Deactivated environment "%s" %s', M.path.basename(virtual_env), virtual_env))
	end
end

-- Simple display of current activated virtual-env
function M.statusline()
	local virtual_env = os.getenv('VIRTUAL_ENV') or ''

	if not (virtual_env == nil or virtual_env == '') then
		return M.path.basename(virtual_env) .. ' ' .. M.config.symbol
	end
	return ''
end

function M.setup(config)
	config = config or {}
	validate({
		auto_activate = { config.auto_activate, 'b', true },
		echo = { config.echo, 'b', true },
		quiet = { config.quiet, 'b', true },
		symbol = { config.symbol, 's', true },
		root_patterns = { config.root_patterns, 't', true },
		use_tools = { config.use_tools, 'b', true },
		tools = { config.use_tools, 't', true },
	})

	M.config = vim.tbl_extend('keep', config, default_config)

	if M.config.auto_activate then
		vim.cmd([[
			augroup venom_plugin
			autocmd!
			autocmd FileType python lua require'venom'.activate()
			augroup END
		]])
	end
end

-- Asynchronous echomsg
function M.echo(type, msg)
	local types = { info = 'Identifier', error = 'ErrorMsg' }
	vim.defer_fn(function()
		M._echo(types[type], msg)
	end, 10)
end

-- Asynchronous echomsg function callback
function M._echo(highlight, msg)
	local msgs = {}
	if type(msg) == 'string' then
		table.insert(msgs, msg)
	else
		msgs = msg
	end
	for _, v in ipairs(msgs) do
		vim.api.nvim_echo({ { '[venom] ' .. v, highlight } }, true, {})
	end
end

return M

-- vim: set ts=2 sw=2 tw=80 noet :
