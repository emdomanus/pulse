--!strict
--!optimize 2
--!native

local main = require(script.Parent.Parent.Parent.roblox_packages.tempo)

export type Clock = main.Clock
export type NativePhase = main.NativePhase
export type PhaseName<PhaseT> = main.PhaseName<PhaseT>
export type Phase<PhaseT> = main.Phase<PhaseT>
export type ScheduledCallback = main.ScheduledCallback
export type PhaseCallback = main.PhaseCallback
export type Options = main.Options
export type Tempo<PhaseT> = main.Tempo<PhaseT>

return main
