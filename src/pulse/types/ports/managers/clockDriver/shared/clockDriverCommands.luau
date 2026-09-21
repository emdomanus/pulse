--!strict
--!optimize 2

local ClockDriverNotifications =
	require(script.Parent.Parent.Parent.Parent.Parent.managers.clockDriver.shared.clockDriver.clockDriverNotifications)

type ClockDriverControlNotification<AttachmentT> = ClockDriverNotifications.ClockDriverControlNotification<AttachmentT>

export type ClockDriverCommands<AttachmentT> = {
	submitControl: (
		self: ClockDriverCommands<AttachmentT>,
		notification: ClockDriverControlNotification<AttachmentT>
	) -> (),
}

return {}
