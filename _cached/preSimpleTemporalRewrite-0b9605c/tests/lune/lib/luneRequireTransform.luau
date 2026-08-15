--!strict

local requireAny = require :: any
local fs = requireAny("@lune/fs")
local process = requireAny("@lune/process")

export type TransformOptions = {
	packageRoot: string,
	tempDir: string,
}

export type TransformHandle = {
	requireModule: (relativePath: string) -> any,
	cleanup: () -> (),
}

local LuneRequireTransform = {}

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

local function discoverPackageFiles(packageRoot: string): { string }
	local discovered: { string } = {}

	local function visit(directoryPath: string, directoryRel: string)
		for _, entry in fs.readDir(directoryPath) do
			local entryPath = joinPath(directoryPath, entry)
			local entryRel = if directoryRel == "" then entry else directoryRel .. "/" .. entry
			if fs.isDir(entryPath) then
				visit(entryPath, entryRel)
			elseif fs.isFile(entryPath) and entry:sub(-5) == ".luau" then
				table.insert(discovered, entryRel)
			end
		end
	end

	visit(packageRoot, "")
	table.sort(discovered)
	return discovered
end

local function moduleSegments(sourceRel: string): { string }
	local withoutExtension = normalizePath(sourceRel):gsub("%.luau$", "")
	local segments: { string } = {}
	for part in withoutExtension:gmatch("[^/]+") do
		table.insert(segments, part)
	end
	if segments[#segments] == "init" then
		table.remove(segments)
	end
	return segments
end

local function relFromSegments(segments: { string }, sourceFileSet: { [string]: true }): string
	local base = table.concat(segments, "/")
	local initRel = if base == "" then "init.luau" else base .. "/init.luau"
	if sourceFileSet[initRel] then
		return initRel
	end
	return base .. ".luau"
end

local function resolveScriptRequire(
	sourceRel: string,
	expression: string,
	tempRoot: string,
	sourceFileSet: { [string]: true }
): string
	local segments = moduleSegments(sourceRel)
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
	return joinPath(tempRoot, relFromSegments(segments, sourceFileSet))
end

function LuneRequireTransform.write(options: TransformOptions): TransformHandle
	local packageRoot = resolveFromCwd(options.packageRoot)
	local tempRoot = resolveFromCwd(options.tempDir)
	local packageFiles = discoverPackageFiles(packageRoot)
	local sourceFileSet: { [string]: true } = {}

	if fs.isDir(tempRoot) then
		fs.removeDir(tempRoot)
	end
	fs.writeDir(tempRoot)

	for _, relativePath in packageFiles do
		sourceFileSet[relativePath] = true
	end

	for _, relativePath in packageFiles do
		local source = fs.readFile(joinPath(packageRoot, relativePath))
		local transformed = source:gsub("require%(%s*(script[^%)]*)%)", function(expression)
			return "require([[" .. resolveScriptRequire(relativePath, expression, tempRoot, sourceFileSet) .. "]])"
		end)

		local targetPath = joinPath(tempRoot, relativePath)
		local targetDir = dirname(targetPath)
		if targetDir ~= "" then
			fs.writeDir(targetDir)
		end
		fs.writeFile(targetPath, transformed)
	end

	return {
		requireModule = function(relativePath: string): any
			return requireAny(joinPath(tempRoot, relativePath))
		end,
		cleanup = function()
			if fs.isDir(tempRoot) then
				fs.removeDir(tempRoot)
			end
		end,
	}
end

return LuneRequireTransform
