local resources = {
	Coins = table.freeze({
		Id = "Coins",
		DisplayName = "Coins",
		Section = "Currencies",
		AttributeName = "PawlandsCoins",
	}),
	Diamonds = table.freeze({
		Id = "Diamonds",
		DisplayName = "Diamonds",
		Section = "Currencies",
		AttributeName = "PawlandsDiamonds",
	}),
	SlimeCore = table.freeze({
		Id = "SlimeCore",
		DisplayName = "Slime Core",
		Section = "Materials",
		AttributeName = "PawlandsSlimeCore",
	}),
}

return table.freeze({
	Resources = table.freeze(resources),

	-- Balances remain integer-safe in Luau's double-precision number range.
	MaxBalance = 9007199254740991,
	MaxLedgerEntries = 100,
	MaxReasonLength = 64,
	MaxSourceLength = 96,
	RevisionAttributeName = "PawlandsEconomyRevision",
})
