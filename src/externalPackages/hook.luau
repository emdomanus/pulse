--!strict
--!optimize 2
--!native

local HookModule = require(script.Parent.Parent.Parent.roblox_packages.hook)

export type Callback<T...> = HookModule.Callback<T...>
export type Hook<T...> = HookModule.Hook<T...>

return HookModule
