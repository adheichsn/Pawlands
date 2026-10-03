return table.freeze({
	SchemaVersion = 2,
	DataStoreName = "PawlandsPlayerProfiles",
	KeyPrefix = "Player_",

	-- Studio defaults to isolated in-memory profiles so local/API-disabled tests do
	-- not kick players or spam DataStore warnings. Enable this only when Studio API
	-- Services are intentionally configured for persistence QA.
	UseDataStoreInStudio = false,

	AutosaveIntervalSeconds = 60,
	SessionLockTimeoutSeconds = 180,
	SessionAcquireAttempts = 6,
	SessionAcquireRetrySeconds = 1.0,
	LoadAttempts = 4,
	SaveAttempts = 3,
	RetryBaseSeconds = 1.0,

	ReadyAttributeName = "PawlandsProfileReady",
	PersistentAttributeName = "PawlandsProfilePersistent",
	FailureAttributeName = "PawlandsProfileLoadFailed",
	LoadFailureKickMessage = "Your Pawlands data could not be loaded safely. Please rejoin.",
})
