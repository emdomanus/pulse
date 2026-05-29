--!strict
--!optimize 2
--!native

local main = require(script.Parent.Parent.Parent.roblox_packages.advancedUtils)

export type HookCallback<T...> = main.HookCallback<T...>
export type HookHandle<T...> = main.HookHandle<T...>

return main

