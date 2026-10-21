return {
	['testburger'] = {
		label = 'Test Burger',
		weight = 220,
		degrade = 60,
		client = {
			image = 'burger_chicken.png',
			status = { hunger = 200000 },
			anim = 'eating',
			prop = 'burger',
			usetime = 2500,
			export = 'ox_inventory_examples.testburger'
		},
		server = {
			export = 'ox_inventory_examples.testburger',
			test = 'what an amazingly delicious burger, amirite?'
		},
		buttons = {
			{
				label = 'Lick it',
				action = function(slot)
					print('You licked the burger')
				end
			},
			{
				label = 'Squeeze it',
				action = function(slot)
					print('You squeezed the burger :(')
				end
			},
			{
				label = 'What do you call a vegan burger?',
				group = 'Hamburger Puns',
				action = function(slot)
					print('A misteak.')
				end
			},
			{
				label = 'What do frogs like to eat with their hamburgers?',
				group = 'Hamburger Puns',
				action = function(slot)
					print('French flies.')
				end
			},
			{
				label = 'Why were the burger and fries running?',
				group = 'Hamburger Puns',
				action = function(slot)
					print('Because they\'re fast food.')
				end
			}
		},
		consume = 0.3
	},

	['bandage'] = {
		label = 'Bandage',
		weight = 115,
		client = {
			anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 },
			prop = { model = `prop_rolled_sock_02`, pos = vec3(-0.14, -0.14, -0.08), rot = vec3(-50.0, -50.0, 0.0) },
			disable = { move = true, car = true, combat = true },
			usetime = 2500,
		}
	},

	['black_money'] = {
		label = 'Dirty Money',
	},

	['burger'] = {
		label = 'Burger',
		weight = 220,
		client = {
			status = { hunger = 200000 },
			anim = 'eating',
			prop = 'burger',
			usetime = 2500,
			notification = 'You ate a delicious burger'
		},
	},

	['sprunk'] = {
		label = 'Sprunk',
		weight = 350,
		client = {
			status = { thirst = 200000 },
			anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
			prop = { model = `prop_ld_can_01`, pos = vec3(0.01, 0.01, 0.06), rot = vec3(5.0, 5.0, -180.5) },
			usetime = 2500,
			notification = 'You quenched your thirst with a sprunk'
		}
	},

	['parachute'] = {
		label = 'Parachute',
		weight = 8000,
		stack = false,
		client = {
			anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d' },
			usetime = 1500
		}
	},

	['garbage'] = {
		label = 'Garbage',
	},

	['paperbag'] = {
		label = 'Paper Bag',
		weight = 1,
		stack = false,
		close = false,
		consume = 0
	},

	['identification'] = {
		label = 'Identification',
		client = {
			image = 'card_id.png'
		}
	},

	['panties'] = {
		label = 'Knickers',
		weight = 10,
		consume = 0,
		client = {
			status = { thirst = -100000, stress = -25000 },
			anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
			prop = { model = `prop_cs_panties_02`, pos = vec3(0.03, 0.0, 0.02), rot = vec3(0.0, -13.5, -1.5) },
			usetime = 2500,
		}
	},

	['lockpick'] = {
		label = 'Lockpick',
		weight = 160,
	},

	['phone'] = {
		label = 'Phone',
		weight = 190,
		stack = false,
		consume = 0,
		client = {
			add = function(total)
				if total > 0 then
					pcall(function() return exports.npwd:setPhoneDisabled(false) end)
				end
			end,

			remove = function(total)
				if total < 1 then
					pcall(function() return exports.npwd:setPhoneDisabled(true) end)
				end
			end
		}
	},

	['money'] = {
		label = 'Money',
	},

	['mustard'] = {
		label = 'Mustard',
		weight = 500,
		client = {
			status = { hunger = 25000, thirst = 25000 },
			anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
			prop = { model = `prop_food_mustard`, pos = vec3(0.01, 0.0, -0.07), rot = vec3(1.0, 1.0, -1.5) },
			usetime = 2500,
			notification = 'You.. drank mustard'
		}
	},

	['water'] = {
		label = 'Water',
		weight = 500,
		client = {
			status = { thirst = 200000 },
			anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
			prop = { model = `prop_ld_flow_bottle`, pos = vec3(0.03, 0.03, 0.02), rot = vec3(0.0, 0.0, -1.5) },
			usetime = 2500,
			cancel = true,
			notification = 'You drank some refreshing water'
		}
	},

	['radio'] = {
		label = 'Radio',
		weight = 1000,
		stack = false,
		allowArmed = true
	},

	['armour'] = {
		label = 'Bulletproof Vest',
		weight = 3000,
		stack = false,
		client = {
			anim = { dict = 'clothingshirt', clip = 'try_shirt_positive_d' },
			usetime = 3500
		}
	},

	['clothing'] = {
		label = 'Clothing',
		consume = 0,
	},

	['mastercard'] = {
		label = 'Fleeca Card',
		stack = false,
		weight = 10,
		client = {
			image = 'card_bank.png'
		}
	},

	['scrapmetal'] = {
		label = 'Scrap Metal',
		weight = 80,
	},

	['pomme'] = {
		label = 'Pomme',
		weight = 150,
		stack = true,
		close = true,
		description = 'Une pomme fraiche du verger de Grapeseed.',
		client = {
			status = { hunger = 80000 },
			anim = 'eating',
			usetime = 2500,
			notification = 'Tu as mange une pomme.',
		},
	},

	['jus_pomme'] = {
		label = 'Jus de pomme',
		weight = 400,
		stack = true,
		close = true,
		description = 'Jus de pomme presse a la main.',
		client = {
			status = { thirst = 200000 },
			anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
			prop = { model = `prop_ld_flow_bottle`, pos = vec3(0.03, 0.03, 0.02), rot = vec3(0.0, 0.0, -1.5) },
			usetime = 2500,
			notification = 'Tu as bu un jus de pomme.',
		},
	},

	-- Lunatic RP : drogues (vendues aux passants) et ingrédients des laboratoires (lunatic_illegal)
	['weed'] = {
		label = 'Pochon de weed',
		weight = 10,
		stack = true,
		description = "Quelques grammes d'herbe, prêts à être vendus.",
	},

	['cocaine'] = {
		label = 'Pochon de cocaïne',
		weight = 10,
		stack = true,
		description = 'Poudre blanche conditionnée pour la revente.',
	},

	['meth'] = {
		label = 'Pochon de meth',
		weight = 10,
		stack = true,
		description = 'Cristaux bleutés, très recherchés.',
	},

	['fentanyl'] = {
		label = 'Fiole de fentanyl',
		weight = 15,
		stack = true,
		description = 'Opioïde de synthèse extrêmement puissant.',
	},

	['weed_leaf'] = {
		label = 'Feuille de cannabis',
		weight = 20,
		stack = true,
	},

	['coca_leaf'] = {
		label = 'Feuille de coca',
		weight = 20,
		stack = true,
	},

	['pseudoephedrine'] = {
		label = 'Pseudoéphédrine',
		weight = 50,
		stack = true,
	},

	['chemicals'] = {
		label = 'Produits chimiques',
		weight = 500,
		stack = true,
	},

	['plastic_bag'] = {
		label = 'Sachet plastique',
		weight = 2,
		stack = true,
	},

	['empty_vial'] = {
		label = 'Fiole vide',
		weight = 10,
		stack = true,
	},

	-- Cannabis : culture et transformation (images déjà présentes dans web/images)
	['weed_seed'] = {
		label = "Graine de cannabis",
		weight = 5,
		stack = true,
		client = { image = 'lemonskunk_seed.png' },
	},

	['weed_bud_untrimmed'] = {
		label = "Tête de cannabis non taillée",
		weight = 30,
		stack = true,
		client = { image = 'marijuana_bud1_untrimmed.png' },
	},

	['weed_bud'] = {
		label = "Tête de cannabis",
		weight = 20,
		stack = true,
		client = { image = 'marijuana_bud1.png' },
	},

	['ground_weed'] = {
		label = "Herbe moulue",
		weight = 10,
		stack = true,
		client = { image = 'ground-weed.png' },
	},

	['weed_jar'] = {
		label = "Bocal de cannabis",
		weight = 300,
		stack = true,
		client = { image = 'marijuana_jar1.png' },
	},

	['weed_brick'] = {
		label = "Brique de cannabis",
		weight = 1000,
		stack = true,
		client = { image = 'brick_weed.png' },
	},

	['hash'] = {
		label = "Haschich",
		weight = 10,
		stack = true,
		client = { image = 'drug_hash.png' },
	},

	['joint'] = {
		label = "Joint",
		weight = 2,
		stack = true,
	},

	['blunt'] = {
		label = "Blunt",
		weight = 3,
		stack = true,
	},

	['bluntwrap'] = {
		label = "Feuille à blunt",
		weight = 1,
		stack = true,
	},

	['bong'] = {
		label = "Bang",
		weight = 400,
		stack = true,
	},

	['hq_soil'] = {
		label = "Terreau de qualité",
		weight = 2000,
		stack = true,
		client = { image = 'hiqualitysoil.png' },
	},

	['lq_soil'] = {
		label = "Terreau",
		weight = 2000,
		stack = true,
		client = { image = 'lowqualitysoil.png' },
	},

	['hq_nutrients'] = {
		label = "Engrais de qualité",
		weight = 500,
		stack = true,
		client = { image = 'hiqualnutrients.png' },
	},

	['lq_nutrients'] = {
		label = "Engrais",
		weight = 500,
		stack = true,
		client = { image = 'lowqualnutrients.png' },
	},

	['manure'] = {
		label = "Bidon de fumier",
		weight = 3000,
		stack = true,
		client = { image = 'manure_can.png' },
	},

	['grow_light'] = {
		label = "Lampe de culture",
		weight = 2500,
		stack = true,
		client = { image = 'light_1.png' },
	},

	['grow_fan'] = {
		label = "Ventilateur de culture",
		weight = 2000,
		stack = true,
		client = { image = 'fan_1.png' },
	},

	-- Cocaïne et crack (images déjà présentes dans web/images)
	['coca_dried'] = {
		label = "Feuilles de coca séchées",
		weight = 20,
		stack = true,
		client = { image = 'coke_driedleaf.png' },
	},

	['cocaine_cut'] = {
		label = "Cocaïne coupée",
		weight = 10,
		stack = true,
	},

	['cocaine_brick'] = {
		label = "Brique de cocaïne",
		weight = 1000,
		stack = true,
		client = { image = 'brick_cocaine.png' },
	},

	['crack'] = {
		label = "Crack",
		weight = 5,
		stack = true,
		client = { image = 'crack_baggy.png' },
	},

	['crack_agent'] = {
		label = "Agent de coupe pour crack",
		weight = 100,
		stack = true,
		client = { image = 'crackmixingagent.png' },
	},

	['ecgonine'] = {
		label = "Ecgonine",
		weight = 50,
		stack = true,
	},

	['bakingsoda'] = {
		label = "Bicarbonate de soude",
		weight = 200,
		stack = true,
	},

	['babypowder'] = {
		label = "Talc",
		weight = 200,
		stack = true,
	},

	['benzene'] = {
		label = "Benzène",
		weight = 1000,
		stack = true,
		client = { image = 'coke_benzene.png' },
	},

	['cement'] = {
		label = "Ciment",
		weight = 2000,
		stack = true,
		client = { image = 'coke_cement.png' },
	},

	-- Opium, héroïne et dérivés (images déjà présentes dans web/images)
	['opium'] = {
		label = "Opium",
		weight = 10,
		stack = true,
		client = { image = 'drug_opium.png' },
	},

	['opium_brick'] = {
		label = "Brique d'opium",
		weight = 1000,
		stack = true,
		client = { image = 'brick_opium.png' },
	},

	['heroin_base'] = {
		label = "Base de morphine",
		weight = 50,
		stack = true,
	},

	['heroin'] = {
		label = "Héroïne",
		weight = 10,
		stack = true,
		client = { image = 'drug_heroin.png' },
	},

	['acetic_anhydride'] = {
		label = "Anhydride acétique",
		weight = 1000,
		stack = true,
		client = { image = 'heroin_anhydride.png' },
	},

	['activated_carbon'] = {
		label = "Charbon actif",
		weight = 300,
		stack = true,
		client = { image = 'heroin_carbon.png' },
	},

	['litmus_paper'] = {
		label = "Papier pH",
		weight = 5,
		stack = true,
		client = { image = 'heroin_litmuspaper.png' },
	},

	['dirty_syringe'] = {
		label = "Seringue usagée",
		weight = 10,
		stack = true,
		client = { image = 'dirtyneedle.png' },
	},

	['codeine'] = {
		label = "Codéine",
		weight = 50,
		stack = true,
	},

	['lean'] = {
		label = "Lean",
		weight = 300,
		stack = true,
	},

	-- Meth et produits chimiques (images déjà présentes dans web/images)
	['meth_brick'] = {
		label = "Brique de meth",
		weight = 1000,
		stack = true,
		client = { image = 'brick_meth.png' },
	},

	['acetone'] = {
		label = "Acétone",
		weight = 1000,
		stack = true,
	},

	['ammonia'] = {
		label = "Ammoniaque",
		weight = 1000,
		stack = true,
	},

	['ammonium_nitrate'] = {
		label = "Nitrate d'ammonium",
		weight = 1000,
		stack = true,
	},

	['lithium'] = {
		label = "Lithium",
		weight = 200,
		stack = true,
	},

	['ephedrine'] = {
		label = "Éphédrine",
		weight = 50,
		stack = true,
	},

	['hydrochloric_acid'] = {
		label = "Acide chlorhydrique",
		weight = 1000,
		stack = true,
		client = { image = 'hydrochloricacid.png' },
	},

	['liquid_sulfur'] = {
		label = "Soufre liquide",
		weight = 1000,
		stack = true,
	},

	['formaldehyde'] = {
		label = "Formaldéhyde",
		weight = 1000,
		stack = true,
	},

	['distilled_water'] = {
		label = "Eau distillée",
		weight = 1000,
		stack = true,
		client = { image = 'distilledwater.png' },
	},

	['iron_oxide'] = {
		label = "Oxyde de fer",
		weight = 500,
		stack = true,
		client = { image = 'ironoxide.png' },
	},

	['aluminum_oxide'] = {
		label = "Oxyde d'aluminium",
		weight = 500,
		stack = true,
		client = { image = 'aluminumoxide.png' },
	},

	['chem_barrel'] = {
		label = "Baril de produits chimiques",
		weight = 20000,
		stack = true,
		client = { image = 'acetonebarrel.png' },
	},

	-- Matériel de laboratoire (images déjà présentes dans web/images)
	['beaker'] = {
		label = "Bécher",
		weight = 200,
		stack = true,
	},

	['empty_chem_bottle'] = {
		label = "Flacon de chimie vide",
		weight = 100,
		stack = true,
		client = { image = 'emptychembottles.png' },
	},

	['chemistry_kit'] = {
		label = "Kit de chimie",
		weight = 5000,
		stack = true,
		client = { image = 'chemistry_station.png' },
	},

	['precision_scale'] = {
		label = "Balance de précision",
		weight = 300,
		stack = true,
		client = { image = 'highqualityscales.png' },
	},

	['gas_mask'] = {
		label = "Masque à gaz",
		weight = 800,
		stack = true,
	},

	-- Autres drogues (images déjà présentes dans web/images)
	['lsd'] = {
		label = "Buvard de LSD",
		weight = 1,
		stack = true,
	},

	['magic_mushroom'] = {
		label = "Champignon hallucinogène",
		weight = 10,
		stack = true,
	},

	['dried_mushroom'] = {
		label = "Champignons séchés",
		weight = 10,
		stack = true,
		client = { image = 'magic_mushrooms_dry.png' },
	},

	['ecstasy'] = {
		label = "Ecstasy",
		weight = 2,
		stack = true,
		client = { image = 'baggy_extasy.png' },
	},

	['pills'] = {
		label = "Gélules",
		weight = 2,
		stack = true,
		client = { image = 'gelpills_red.png' },
	},

	-- Nourriture (images déjà présentes dans web/images)
	['donut'] = {
		label = "Donut",
		weight = 120,
		stack = true,
	},

	['fries'] = {
		label = "Frites",
		weight = 150,
		stack = true,
	},

	['pizza_ham'] = {
		label = "Pizza jambon",
		weight = 800,
		stack = true,
	},

	['pizza_ham_slice'] = {
		label = "Part de pizza",
		weight = 150,
		stack = true,
	},

	-- Divers (images déjà présentes dans web/images)
	['key'] = {
		label = "Clé",
		weight = 10,
		stack = true,
	},

	['carkey'] = {
		label = "Clé de voiture",
		weight = 10,
		stack = true,
	},

	['elock'] = {
		label = "Serrure électronique",
		weight = 300,
		stack = true,
	},

	['usb'] = {
		label = "Clé USB",
		weight = 10,
		stack = true,
		client = { image = 'usb_black.png' },
	},

	['burner_phone'] = {
		label = "Téléphone jetable",
		weight = 150,
		stack = true,
		client = { image = 'drug_phone.png' },
	},

	['ziptie'] = {
		label = "Collier de serrage",
		weight = 5,
		stack = true,
	},

	['medikit'] = {
		label = "Trousse de soins",
		weight = 500,
		stack = true,
	},

	['advancedkit'] = {
		label = "Kit de réparation avancé",
		weight = 2000,
		stack = true,
	},

	['cigarette'] = {
		label = "Cigarette",
		weight = 1,
		stack = true,
	},

	['cigarette_pack'] = {
		label = "Paquet de cigarettes",
		weight = 30,
		stack = true,
		client = { image = 'cigarettes_redwood.png' },
	},

	['empty_bottle'] = {
		label = "Bouteille vide",
		weight = 200,
		stack = true,
	},

	['empty_package'] = {
		label = "Colis vide",
		weight = 200,
		stack = true,
	},

	-- Pièces d'armes (craft d'armes des crews) (images déjà présentes dans web/images)
	['gun_barrel'] = {
		label = "Canon d'arme",
		weight = 400,
		stack = true,
	},

	['gun_slide'] = {
		label = "Culasse",
		weight = 300,
		stack = true,
	},

	['gun_spring'] = {
		label = "Ressort de détente",
		weight = 20,
		stack = true,
	},

	['gun_stock'] = {
		label = "Crosse",
		weight = 600,
		stack = true,
	},

	['gunpowder'] = {
		label = "Poudre à canon",
		weight = 50,
		stack = true,
	},

	['bullet_casing'] = {
		label = "Douille",
		weight = 5,
		stack = true,
	},
}
