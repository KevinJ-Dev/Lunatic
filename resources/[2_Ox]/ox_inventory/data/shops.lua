-- Lunatic RP : les magasins (LTD, Ammunation, armurerie de police…) sont gérés depuis le panel staff
-- (lunatic_admin, tuile Catalogues) et enregistrés dynamiquement par lunatic_business.
-- Seuls les distributeurs automatiques restent ici. Fichier d'origine : historique Git (commit 08819be).
return {
	VendingMachineDrinks = {
		name = 'Vending Machine',
		inventory = {
			{ name = 'water', price = 10 },
			{ name = 'cola', price = 10 },
		},
		model = {
			`prop_vend_soda_02`, `prop_vend_fridge01`, `prop_vend_water_01`, `prop_vend_soda_01`
		}
	}
}
