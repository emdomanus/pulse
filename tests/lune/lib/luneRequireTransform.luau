--!strict

type RequireUnknown = (path: string) -> unknown
type FileSystem = {
	readDir: (path: string) -> { string },
	isDir: (path: string) -> boolean,
	isFile: (path: string) -> boolean,
	removeDir: (path: string) -> (),
	writeDir: (path: string) -> (),
	readFile: (path: string) -> string,
	writeFile: (path: string, contents: string) -> (),
}
type Process = {
	cwd: string,
}

local requireUnknown = (require :: unknown) :: RequireUnknown
local fs = (requireUnknown("@lune/fs") :: unknown) :: FileSystem
local process = (requireUnknown("@lune/process") :: unknown) :: Process

export type TransformOptions = {
	packageRoot: string,
	tempDir: string,
}

export type TransformHandle = {
	requireModule: (relativePath: string) -> unknown,
	cleanup: () -> (),
}

local Transform = {}

local function normalizePath(path: string): string
	return (path:gsub("\\", "/"))
end

local function joinPath(left: string, right: string): string
	if left:sub(-1) == "/" or left:sub(-1) == "\\" then
		return left .. right
	end
	return left .. "/" .. right
end

local function resolveFromCwd(path: string): string
	local normalized = normalizePath(path)
	if normalized:match("^%a:/") or normalized:sub(1, 1) == "/" then
		return normalized
	end
	return joinPath(process.cwd, normalized)
end

local function dirname(path: string): string
	return normalizePath(path):match("^(.*)/[^/]+$") or ""
end

local function discoverFiles(packageRoot: string): { string }
	local discovered: { string } = {}
	local function visit(directoryPath: string, directoryRelative: string)
		for _, entry in fs.readDir(directoryPath) do
			local entryPath = joinPath(directoryPath, entry)
			local relative = if directoryRelative == "" then entry else directoryRelative .. "/" .. entry
			if fs.isDir(entryPath) then
				visit(entryPath, relative)
			elseif fs.isFile(entryPath) and entry:sub(-5) == ".luau" then
				table.insert(discovered, relative)
			end
		end
	end
	visit(packageRoot, "")
	table.sort(discovered)
	return discovered
end

local function moduleSegments(sourceRelative: string): { string }
	local withoutExtension = normalizePath(sourceRelative):gsub("%.luau$", "")
	local segments: { string } = {}
	for part in withoutExtension:gmatch("[^/]+") do
		table.insert(segments, part)
	end
	if segments[#segments] == "init" then
		table.remove(segments)
	end
	return segments
end

local function relativeFromSegments(segments: { string }, files: { [string]: true }): string
	local base = table.concat(segments, "/")
	local initRelative = if base == "" then "init.luau" else base .. "/init.luau"
	return if files[initRelative] then initRelative else base .. ".luau"
end

local function resolveScriptRequire(
	sourceRelative: string,
	expression: string,
	tempRoot: string,
	files: { [string]: true }
): string
	local segments = moduleSegments(sourceRelative)
	local first = true
	for token in expression:gmatch("[A-Za-z_][A-Za-z0-9_]*") do
		if first then
			first = false
		elseif token == "Parent" then
			table.remove(segments)
		else
			table.insert(segments, token)
		end
	end
	return joinPath(tempRoot, relativeFromSegments(segments, files))
end

function Transform.write(options: TransformOptions): TransformHandle
	local packageRoot = resolveFromCwd(options.packageRoot)
	local tempRoot = resolveFromCwd(options.tempDir)
	local packageFiles = discoverFiles(packageRoot)
	local fileSet: { [string]: true } = {}
	if fs.isDir(tempRoot) then
		fs.removeDir(tempRoot)
	end
	fs.writeDir(tempRoot)
	for _, relative in packageFiles do
		fileSet[relative] = true
	end
	for _, relative in packageFiles do
		local source = fs.readFile(joinPath(packageRoot, relative))
		local transformed = source:gsub("require%(%s*(script[^%)]*)%)", function(expression: string): string
			local resolved = resolveScriptRequire(relative, expression, tempRoot, fileSet)
			return "require([[" .. resolved .. "]])"
		end)
		local target = joinPath(tempRoot, relative)
		local targetDirectory = dirname(target)
		if targetDirectory ~= "" then
			fs.writeDir(targetDirectory)
		end
		fs.writeFile(target, transformed)
	end
	return {
		requireModule = function(relativePath: string): unknown
			return requireUnknown(joinPath(tempRoot, relativePath))
		end,
		cleanup = function()
			if fs.isDir(tempRoot) then
				fs.removeDir(tempRoot)
			end
		end,
	}
end

return Transform
