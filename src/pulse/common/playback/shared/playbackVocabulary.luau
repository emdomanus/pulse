--!strict
--!optimize 2

export type TraversalDirection = "forward" | "backward"
export type AddressMode = "reconstruct" | "skip"
export type AddressCause = "initial" | "seek"
export type ActiveStatus = "idle" | "playing" | "paused"
export type TerminalStatus = "completed" | "cancelled" | "destroyed" | "failed"
export type Status = ActiveStatus | TerminalStatus

return {}
