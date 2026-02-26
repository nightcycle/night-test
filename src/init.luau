--!strict
-- Services
-- Packages
-- Modules
local Parameter = require(script.Parameter)
local Test = require(script.Test)
local Debug = require(script.Debug)
local Summary = require(script.Summary)
local ENV = require(script.ENV)
-- Types
export type Test = Test.Test
export type TestMap = Test.TestMap
export type TestTree = Test.TestTree
export type TestResult = Test.TestResult
export type Parameter = Parameter.Parameter
export type Summary = Summary.Summary
export type SummaryType = Summary.SummaryType
export type JSONValue = Parameter.JSONValue
-- Constants
local CONSTANTS = require(script.CONSTANTS)
-- Variables
-- References
-- Private Functions
function toPath(inst: Instance): string
	local path = inst:GetFullName()
	path = path:gsub("%.spec", ""):gsub("%.", "/")
	return path
end

-- Class
local Module = {}

Module.CONSTANTS = CONSTANTS
Module.Parameter = Parameter
Module.Summary = Summary
Module.Test = Test
Module.Debug = Debug
Module.ENV = ENV

Module.searchFromEnv = function(): TestMap
	local path = ENV.SEARCH_FILTER_PATH
	if path == "" then
		error("SEARCH_FILTER_PATH is not set")
	else
		local inst: Instance = game
		local splitPath = path
		if path:sub(-5) == ".luau" then
			splitPath = path:sub(1, -6)
		elseif path:sub(-4) == ".lua" then
			splitPath = path:sub(1, -5)
		end
		local segments: { string } = string.split(splitPath, "/")
		if segments[1] == "game" or segments[1] == "src" then
			table.remove(segments, 1)
		end
		repeat
			local segment = segments[1]
			if not segment then
				error(`Invalid SEARCH_FILTER_PATH: "{path}"`)
			end
			local child = inst:FindFirstChild(segment)
			if child == nil then
				error(`Invalid SEARCH_FILTER_PATH, could not find instance at segment "{segment}": "{path}"`)
			end
			inst = child
			table.remove(segments, 1)
		until #segments == 0
		return Module.search({ inst })
	end
end

Module.search = function(instances: { Instance }): TestMap
	local out: { [string]: Test } = {}
	for _, instance in instances do
		if instance:IsA("ModuleScript") and instance.Name:sub(-5) == ".spec" then
			local success, module = pcall(require, instance)
			if success then
				do
					local isTest, _err = Test.Type.Test(module)
					if isTest then
						local path = toPath(instance)
						assert(out[path] == nil, `duplicate path at: "path}"`)
						out[path] = module
						continue
					end
				end
				do
					local isTestMap, _err = Test.Type.TestMap(module)
					if isTestMap then
						local path = toPath(instance)
						for k, v in module do
							local keyPath = `{path}/{k}`
							assert(out[keyPath] == nil, `duplicate path at: "{keyPath}"`)
							out[keyPath] = v
						end
						continue
					end
				end
				do
					local isTestTree, _err = Test.Type.TestTree(module)
					if isTestTree then
						local path = toPath(instance)
						local toAdd: { [string]: Test } = {}
						local function recurse(tree: Test.TestTree, currentPath: string): boolean
							for k, v in tree do
								local keyPath = `{currentPath}/{k}`
								assert(toAdd[keyPath] == nil, `duplicate path at: "{keyPath}"`)
								if Test.Type.Test(v) then
									toAdd[keyPath] = v :: Test.Test
								elseif Test.Type.TestTree(v) then
									recurse(v :: Test.TestTree, keyPath)
								else
									return false
								end
							end
							return true
						end
						recurse(module, path)
						for k, v in toAdd do
							assert(out[k] == nil, `duplicate path at: "{k}"`)
							out[k] = v
						end
						continue
					end
				end
			end
		end
	end
	table.freeze(out)
	return out
end

Module.run = function(tests: TestMap, summaryType: SummaryType): Summary
	Debug.log(`Running tests...`)
	local results: { [string]: { TestResult } } = {}
	for path, test in tests do
		Debug.log(`Running test: "{path}"`)
		results[path] = Test.run(test)
	end
	Debug.log("Completed running tests")
	if summaryType == "FullJSON" then
		return Summary.newFullJSON(results)
	elseif summaryType == "Overview" then
		return Summary.newOverview(results)
	else
		error(`Invalid summary type: "{summaryType}"`)
	end
end

return Module
