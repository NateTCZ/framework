--!strict

return table.freeze({
	NAME = "Framework",
	NETWORK_ROOT = "__FrameworkNetwork",
	SIGNALS = "Signals",
	CLIENT_SIGNALS = "ClientSignals",
	METHODS = "Methods",
	PROPERTIES = "Properties",
	PROPERTY_SNAPSHOT = "PropertySnapshot",
	READY = "Ready",
	REMOTE_TIMEOUT = 10,
	-- Minimum seconds between repeated warnings for the same player and endpoint.
	WARN_INTERVAL = 5,
})
