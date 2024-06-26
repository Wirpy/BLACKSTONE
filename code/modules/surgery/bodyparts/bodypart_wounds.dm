/obj/item/bodypart
	/// List of /datum/wound instances affecting this bodypart
	var/list/wounds
	/// Bandage
	var/obj/item/bandage

/// Returns all wounds on this limb that can be sewn
/obj/item/bodypart/proc/get_sewable_wounds()
	var/list/woundies = list()
	for(var/datum/wound/wound as anything in wounds)
		if(!wound.can_sew)
			continue
		woundies += wound
	return woundies

/// Check to see if we can apply a bleeding wound on this bodypart
/obj/item/bodypart/proc/can_bloody_wound()
	if(skeletonized)
		return FALSE
	if(!is_organic_limb())
		return FALSE
	if(NOBLOOD in owner?.dna?.species?.species_traits)
		return FALSE
	return TRUE

/// Returns the total bleed rate on this bodypart
/obj/item/bodypart/proc/get_bleed_rate()
	var/bleed_rate = 0
	if(bandage && !HAS_BLOOD_DNA(bandage))
		return 0
	for(var/datum/wound/wound as anything in wounds)
		bleed_rate += wound.bleed_rate
	//I hate that I have to do this shit
	listclearnulls(embedded_objects)
	for(var/obj/item/embedded as anything in embedded_objects)
		if(!embedded.embedding.embedded_bloodloss)
			continue
		bleed_rate += embedded.embedding.embedded_bloodloss
	for(var/obj/item/grabbing/grab in grabbedby)
		bleed_rate *= grab.bleed_suppressing
	bleed_rate = max(round(bleed_rate, 0.1), 0)
	return bleed_rate

/// Returns the first wound of the specified type on this bodypart
/obj/item/bodypart/proc/has_wound(path, specific = FALSE)
	if(!path)
		return
	for(var/datum/wound/wound as anything in wounds)
		if((specific && wound.type != path) || !istype(wound, path))
			continue
		return wound

/// Adds a wound to this bodypart, applying any necessary effects
/obj/item/bodypart/proc/add_wound(datum/wound/wound, silent = FALSE, crit_message = FALSE)
	if(!wound || !owner || (owner.status_flags & GODMODE))
		return
	if(ispath(wound, /datum/wound))
		var/datum/wound/primordial_wound = GLOB.primordial_wounds[wound]
		if(!primordial_wound.can_apply_to_bodypart(src))
			return
		wound = new wound()
	else if(!istype(wound))
		return
	else if(!wound.can_apply_to_bodypart(src))
		qdel(wound)
		return
	if(!wound.apply_to_bodypart(src, silent, crit_message))
		qdel(wound)
		return
	return wound

/// Removes a wound from this bodypart, removing any associated effects
/obj/item/bodypart/proc/remove_wound(datum/wound/wound)
	if(ispath(wound))
		wound = has_wound(wound)
	if(!istype(wound))
		return FALSE
	. = wound.remove_from_bodypart()
	if(.)
		qdel(wound)

/// Heals wounds on this bodypart by the specified amount
/obj/item/bodypart/proc/heal_wounds(heal_amount)
	if(!length(wounds))
		return FALSE
	var/healed_any = FALSE
	for(var/datum/wound/wound as anything in wounds)
		if(heal_amount <= 0)
			continue
		var/amount_healed = wound.heal_wound(heal_amount)
		heal_amount -= amount_healed
		healed_any = TRUE
	return healed_any

/// Called after a bodypart is attacked so that wounds and critical effects can be applied
/obj/item/bodypart/proc/bodypart_attacked_by(bclass, dam, mob/living/user, zone_precise, silent = FALSE, crit_message = FALSE)
	if(!bclass || !dam || !owner || (owner.status_flags & GODMODE))
		return FALSE
	if(ishuman(owner))
		var/mob/living/carbon/human/human_owner = owner
		if(human_owner.checkcritarmor(zone_precise, bclass))
			return FALSE
	var/do_crit = TRUE
	if(user)
		if(user.goodluck(2))
			dam += 10
		if(istype(user.rmb_intent, /datum/rmb_intent/weak))
			do_crit = FALSE
	testing("bodypart_attacked_by() dam [dam]")
	var/added_wound
	switch(bclass) //do stuff but only when we are a blade that adds wounds
		if(BCLASS_SMASH, BCLASS_BLUNT)
			switch(dam)
				if(20 to INFINITY)
					added_wound = /datum/wound/bruise/large
				if(10 to 20)
					added_wound = /datum/wound/bruise
				if(1 to 10)
					added_wound = /datum/wound/bruise/small
		if(BCLASS_CUT, BCLASS_CHOP)
			switch(dam)
				if(20 to INFINITY)
					added_wound = /datum/wound/slash/large
				if(10 to 20)
					added_wound = /datum/wound/slash
				if(1 to 10)
					added_wound = /datum/wound/slash/small
		if(BCLASS_STAB, BCLASS_PICK)
			switch(dam)
				if(20 to INFINITY)
					added_wound = /datum/wound/puncture/large
				if(10 to 20)
					added_wound = /datum/wound/puncture
				if(1 to 10)
					added_wound = /datum/wound/puncture/small
		if(BCLASS_BITE)
			switch(dam)
				if(20 to INFINITY)
					added_wound = /datum/wound/bite/large
				if(10 to 20)
					added_wound = /datum/wound/bite
				if(1 to 10)
					added_wound = /datum/wound/bite/small
	if(added_wound)
		added_wound = add_wound(added_wound, silent, crit_message)
	if(do_crit)
		var/crit_attempt = try_crit(bclass, dam, user, zone_precise, silent, crit_message)
		if(crit_attempt)
			return crit_attempt
	return added_wound

/// Behemoth of a proc used to apply a wound after a bodypart is damaged in an attack
/obj/item/bodypart/proc/try_crit(bclass, dam, mob/living/user, zone_precise, silent = FALSE, crit_message = FALSE)
	if(!bclass || !dam || (owner.status_flags & GODMODE))
		return FALSE
	var/list/attempted_wounds = list()
	var/used
	var/total_dam = get_damage()
	var/damage_dividend = (total_dam / max_damage)
	if(user && dam)
		if(user.goodluck(2))
			dam += 10
	if(bclass in GLOB.dislocation_bclasses)
		used = round(damage_dividend * 20 + (dam / 3), 1)
		if(user && istype(user.rmb_intent, /datum/rmb_intent/strong))
			used += 10
		if(prob(used))
			if(HAS_TRAIT(src, TRAIT_BRITTLE))
				attempted_wounds += /datum/wound/fracture
			else
				attempted_wounds += /datum/wound/dislocation
	if(bclass in GLOB.fracture_bclasses)
		used = round(damage_dividend * 20 + (dam / 3), 1)
		if(user)
			if(istype(user.rmb_intent, /datum/rmb_intent/strong))
				used += 10
		if(HAS_TRAIT(src, TRAIT_BRITTLE))
			used += 10
		if(prob(used))
			attempted_wounds += /datum/wound/fracture
	if(bclass in GLOB.artery_bclasses)
		used = round(damage_dividend * 20 + (dam / 3), 1)
		if(user)
			if((bclass in GLOB.artery_strong_bclasses) && istype(user.rmb_intent, /datum/rmb_intent/strong))
				used += 10
			else if(istype(user.rmb_intent, /datum/rmb_intent/aimed))
				used += 10
		if(prob(used))
			attempted_wounds += /datum/wound/artery

	for(var/wound_type in shuffle(attempted_wounds))
		var/datum/wound/applied = add_wound(wound_type, silent, crit_message)
		if(applied)
			return applied
	return FALSE

/obj/item/bodypart/chest/try_crit(bclass, dam, mob/living/user, zone_precise, silent = FALSE, crit_message = FALSE)
	if(!bclass || !dam || (owner.status_flags & GODMODE))
		return FALSE
	var/list/attempted_wounds = list()
	var/used
	var/total_dam = get_damage()
	var/damage_dividend = (total_dam / max_damage)
	var/resistance = HAS_TRAIT(owner, TRAIT_CRITICAL_RESISTANCE)
	if(user && dam)
		if(user.goodluck(2))
			dam += 10
	if((bclass in GLOB.cbt_classes) && (zone_precise == BODY_ZONE_PRECISE_GROIN))
		var/cbt_multiplier = 1
		if(user && HAS_TRAIT(user, TRAIT_NUTCRACKER))
			cbt_multiplier = 2
		if(!resistance && prob(round(dam/5) * cbt_multiplier))
			attempted_wounds += /datum/wound/cbt
		if(prob(dam * cbt_multiplier))
			owner.emote("groin", TRUE)
			owner.Stun(10)
	if((bclass in GLOB.fracture_bclasses) && (zone_precise != BODY_ZONE_PRECISE_STOMACH))
		used = round(damage_dividend * 20 + (dam / 3), 1)
		if(user && istype(user.rmb_intent, /datum/rmb_intent/strong))
			used += 10
		if(HAS_TRAIT(src, TRAIT_BRITTLE))
			used += 10
		var/fracture_type = /datum/wound/fracture/chest
		if(zone_precise == BODY_ZONE_PRECISE_GROIN)
			fracture_type = /datum/wound/fracture/groin
		if(prob(used))
			attempted_wounds += fracture_type
	if(bclass in GLOB.artery_bclasses)
		used = round(damage_dividend * 20 + (dam / 4), 1)
		if(user)
			if((bclass in GLOB.artery_strong_bclasses) && istype(user.rmb_intent, /datum/rmb_intent/strong))
				used += 10
			else if(istype(user.rmb_intent, /datum/rmb_intent/aimed))
				used += 10
		if(prob(used))
			if((zone_precise == BODY_ZONE_PRECISE_STOMACH) && !resistance)
				attempted_wounds += /datum/wound/slash/disembowel
			attempted_wounds += /datum/wound/artery/chest

	for(var/wound_type in shuffle(attempted_wounds))
		var/datum/wound/applied = add_wound(wound_type, silent, crit_message)
		if(applied)
			return applied
	return FALSE

/obj/item/bodypart/head/try_crit(bclass, dam, mob/living/user, zone_precise, silent = FALSE, crit_message = FALSE)
	var/static/list/eyestab_zones = list(BODY_ZONE_PRECISE_R_EYE, BODY_ZONE_PRECISE_L_EYE)
	var/static/list/tonguestab_zones = list(BODY_ZONE_PRECISE_MOUTH)
	var/static/list/nosestab_zones = list(BODY_ZONE_PRECISE_NOSE)
	var/static/list/earstab_zones = list(BODY_ZONE_PRECISE_EARS)
	var/static/list/knockout_zones = list(BODY_ZONE_HEAD, BODY_ZONE_PRECISE_SKULL)
	var/list/attempted_wounds = list()
	var/used
	var/total_dam = get_damage()
	var/damage_dividend = (total_dam / max_damage)
	var/resistance = HAS_TRAIT(owner, TRAIT_CRITICAL_RESISTANCE)
	var/from_behind = FALSE
	if(user && (owner.dir == turn(get_dir(owner,user), 180)))
		from_behind = TRUE
	if(user && dam)
		if(user.goodluck(2))
			dam += 10
	if((bclass in GLOB.dislocation_bclasses) && (total_dam >= max_damage))
		used = round(damage_dividend * 20 + (dam / 3), 1)
		if(prob(used))
			if(HAS_TRAIT(src, TRAIT_BRITTLE))
				attempted_wounds += /datum/wound/fracture/neck
			else
				attempted_wounds += /datum/wound/dislocation/neck
	if(bclass in GLOB.fracture_bclasses)
		used = round(damage_dividend * 20 + (dam / 3), 1)
		if(HAS_TRAIT(src, TRAIT_BRITTLE))
			used += 20
		if(user)
			if(istype(user.rmb_intent, /datum/rmb_intent/strong))
				used += 10
		if(!owner.stat && (zone_precise in knockout_zones) && (bclass != BCLASS_CHOP) && prob(used))
			owner.next_attack_msg += " <span class='crit'><b>Critical hit!</b> [owner] is knocked out[from_behind ? " FROM BEHIND" : ""]!</span>"
			owner.flash_fullscreen("whiteflash3")
			owner.Unconscious(5 SECONDS + (from_behind * 10 SECONDS))
			if(owner.client)
				winset(owner.client, "outputwindow.output", "max-lines=1")
				winset(owner.client, "outputwindow.output", "max-lines=100")
		var/fracture_type = /datum/wound/fracture/head
		var/necessary_damage = 0.9
		if(resistance)
			fracture_type = /datum/wound/fracture
		else if(zone_precise == BODY_ZONE_PRECISE_SKULL)
			necessary_damage = 0.8
			used += 5
		else if(zone_precise == BODY_ZONE_PRECISE_MOUTH)
			fracture_type = /datum/wound/fracture/mouth
			necessary_damage = 0.6
		else if(zone_precise == BODY_ZONE_PRECISE_NECK)
			fracture_type = /datum/wound/fracture/neck
			necessary_damage = 0.9
		if(prob(used) && (damage_dividend >= necessary_damage))
			attempted_wounds += fracture_type
	if(bclass in GLOB.artery_bclasses)
		used = round(damage_dividend * 20 + (dam / 3), 1)
		if(user)
			if(bclass == BCLASS_CHOP)
				if(istype(user.rmb_intent, /datum/rmb_intent/strong))
					used += 10
			else
				if(istype(user.rmb_intent, /datum/rmb_intent/aimed))
					used += 10
		var/artery_type = /datum/wound/artery
		if(zone_precise == BODY_ZONE_PRECISE_NECK)
			artery_type = /datum/wound/artery/neck
		if(prob(used))
			attempted_wounds += artery_type
			if((bclass in GLOB.stab_bclasses) && !resistance)
				if(zone_precise in eyestab_zones)
					var/obj/item/organ/eyes/my_eyes = owner.getorganslot(ORGAN_SLOT_EYES)
					if(my_eyes)
						playsound(owner, 'sound/combat/crit.ogg', 100, FALSE)
						owner.Stun(5)
						owner.blind_eyes(5)
						if(zone_precise == BODY_ZONE_PRECISE_R_EYE)
							my_eyes.right_poked = TRUE
							if(!my_eyes.left_poked)
								owner.next_attack_msg += " <span class='crit'><b>Critical hit!</b> The right eye is poked out!</span>"
						else
							my_eyes.left_poked = TRUE
							if(!my_eyes.right_poked)
								owner.next_attack_msg += " <span class='crit'><b>Critical hit!</b> The left eye is poked out!</span>"
						if(my_eyes.right_poked && my_eyes.left_poked)
							owner.next_attack_msg += " <span class='crit'><b>Critical hit!</b> The eyes are gored!</span>"
							my_eyes.forceMove(get_turf(owner))
							my_eyes.Remove(owner)
						owner.update_fov_angles()
					else
						attempted_wounds += /datum/wound/fracture/head/eyes
				else if(zone_precise in tonguestab_zones)
					var/obj/item/organ/tongue/tongue_up_my_asshole = owner.getorganslot(ORGAN_SLOT_TONGUE)
					if(tongue_up_my_asshole)
						playsound(owner, 'sound/combat/crit.ogg', 100, FALSE)
						owner.next_attack_msg += " <span class='crit'><b>Critical hit!</b> The tongue flies off in an arc!</span>"
						owner.Stun(10)
						tongue_up_my_asshole.forceMove(get_turf(owner))
						tongue_up_my_asshole.Remove(owner)
					else
						attempted_wounds += /datum/wound/fracture/mouth
				else if(zone_precise in nosestab_zones)
					if(!has_wound(/datum/wound/nose))
						attempted_wounds += /datum/wound/nose
					else if(!has_wound(/datum/wound/fracture/head/nose))
						attempted_wounds +=/datum/wound/fracture/head/nose
				else if(zone_precise in earstab_zones)
					var/obj/item/organ/ears/my_ears = owner.getorganslot(ORGAN_SLOT_EARS)
					if(my_ears)
						owner.next_attack_msg += " <span class='crit'><b>Critical hit!</b> The eardrums are ruptured!</span>"
						playsound(owner, 'sound/combat/crit.ogg', 100, FALSE)
						owner.Stun(10)
						my_ears.forceMove(get_turf(owner))
						my_ears.Remove(owner)
					else 
						attempted_wounds += /datum/wound/fracture/head/ears
				else if(zone_precise in knockout_zones)
					attempted_wounds += /datum/wound/fracture/head/brain

	for(var/wound_type in shuffle(attempted_wounds))
		var/datum/wound/applied = add_wound(wound_type, silent, crit_message)
		if(applied)
			return applied
	return FALSE

/// Applies a temporary paralysis effect to this bodypart
/obj/item/bodypart/proc/temporary_crit_paralysis(duration = 60 SECONDS, brittle = TRUE)
	if(HAS_TRAIT(src, TRAIT_BRITTLE))
		return FALSE
	ADD_TRAIT(src, TRAIT_PARALYSIS, CRIT_TRAIT)
	if(brittle)
		ADD_TRAIT(src, TRAIT_BRITTLE, CRIT_TRAIT)
	addtimer(CALLBACK(src, PROC_REF(remove_crit_paralysis)), duration)
	if(owner)
		update_disabled()
	return TRUE

/// Removes the temporary paralysis effect from this bodypart
/obj/item/bodypart/proc/remove_crit_paralysis()
	REMOVE_TRAIT(src, TRAIT_PARALYSIS, CRIT_TRAIT)
	REMOVE_TRAIT(src, TRAIT_BRITTLE, CRIT_TRAIT)
	if(owner)
		update_disabled()
	return TRUE

/obj/item/bodypart/proc/try_bandage(obj/item/new_bandage)
	if(!new_bandage)
		return FALSE
	bandage = new_bandage
	new_bandage.forceMove(src)
	return TRUE

/obj/item/bodypart/proc/try_bandage_expire()
	if(!bandage)
		return FALSE
	var/bandage_effectiveness = 0.5
	if(istype(bandage, /obj/item/natural/cloth))
		var/obj/item/natural/cloth/cloth = bandage
		bandage_effectiveness = cloth.bandage_effectiveness
	var/highest_bleed_rate = 0
	for(var/datum/wound/wound as anything in wounds)
		if(wound.bleed_rate < highest_bleed_rate)
			continue
		highest_bleed_rate = wound.bleed_rate
	//I hate that I have to do this shit
	listclearnulls(embedded_objects)
	for(var/obj/item/embedded as anything in embedded_objects)
		if(!embedded.embedding.embedded_bloodloss)
			continue
		if(embedded.embedding.embedded_bloodloss < highest_bleed_rate)
			continue
		highest_bleed_rate = embedded.embedding.embedded_bloodloss
	highest_bleed_rate = round(highest_bleed_rate, 0.1)
	if(bandage_effectiveness < highest_bleed_rate)
		return bandage_expire()
	return FALSE

/obj/item/bodypart/proc/bandage_expire()
	testing("expire bandage")
	if(!owner)
		return FALSE
	if(!bandage)
		return FALSE
	if(owner.stat != DEAD)
		to_chat(owner, "<span class='warning'>Blood soaks through the bandage on my [name].</span>")
	return bandage.add_mob_blood(owner)
