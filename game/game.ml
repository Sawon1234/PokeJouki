open Definitions
open Util
open Constants
open Netgraphics
open State
open Action_handler

let _ = Random.self_init ()

(* You have to implement this. Change it from int to your own state type*)
type game = mgame_status_data


(* An empty list to be filled in when steammon.txt is read *)
let steammon_list = ref [] and attack_list = ref []


let find_speed mon =
  let find_speed_mod speed_mod = match speed_mod with
                                           | -3 -> cSPEED_DOWN3
                                           | -2 -> cSPEED_DOWN2
                                           | -1 -> cSPEED_DOWN1
                                           | 1 -> cSPEED_UP1
                                           | 2 -> cSPEED_UP2
                                           | 3 -> cSPEED_UP3
                                           | _ -> 1. in
  let speed_mod = find_speed_mod (mon.mmods).mspeed_mod in    
  let speed = float_of_int mon.mspeed
  and slow = float_of_int cPARALYSIS_SLOW in
  if (List.mem Paralyzed mon.mstatus) then speed *. speed_mod /. slow
  else speed *. speed_mod


(* Converts from type Game.game to Definitions.game_status_data *)
let game_datafication (g : game) : game_status_data =
  (* Converts item_count from an int ref to an int and adds it to the acc list *)
  let inventory_datafication acc item_count = !item_count::acc in
  (* Returns an object of type Definitions.game_status_data *)
  let (msteammons1, minventory1), (msteammons2, minventory2) = g in
  let helper acc msteammon = (steammon_datafication msteammon)::acc in
  let steammons1 = List.fold_left helper [] !msteammons1 in
  let steammons2 = List.fold_left helper [] !msteammons2 in
  let inventory1 = List.fold_left inventory_datafication [] minventory1 in
  let inventory2 = List.fold_left inventory_datafication [] minventory2 in
  (List.rev steammons1, List.rev inventory1), 
  (List.rev steammons2, List.rev inventory2)


(* Converts an object of type Definitions.game_status_data to Game.game *)
let game_from_data (game_data : game_status_data) : game =
  (* Converts item_count from type int to int ref and adds it to the acc list *)
  let inventory_mutafication acc item_count = (ref item_count)::acc in
  (* Returns an object of type Game.game *)
  let (steammons1, inventory1), (steammons2, inventory2) = game_data in
  let helper acc steammon = (steammon_mutafication steammon)::acc in
  let msteammons1 = List.fold_left helper [] steammons1 in
  let msteammons2 = List.fold_left helper [] steammons2 in
  let minventory1 = List.fold_left inventory_mutafication [] inventory1 in
  let minventory2 = List.fold_left inventory_mutafication [] inventory2 in
  (ref (List.rev msteammons1), List.rev minventory1), 
  (ref (List.rev msteammons2), List.rev minventory2)

(* Handles a step in the game *)
let handle_step (g : game) (ra : command) (ba : command) : game_output =
  (* Functions to see if m has the given status *)
  let asleep m = List.mem Asleep m.mstatus
  and frozen m = List.mem Frozen m.mstatus
  and confused m = List.mem Confused m.mstatus
  and poisoned m = List.mem Poisoned m.mstatus in
  (* Functions to remove the given status from m *)
  let wake_up m = m.mstatus <- List.filter (fun x -> x <> Asleep) m.mstatus 
  and snap_out m = m.mstatus <- List.filter (fun x -> x <> Confused) m.mstatus 
  and defrost m = m.mstatus <- List.filter (fun x -> x <> Frozen) m.mstatus in
  (* Functions to remove status with a certain probability or apply poison *)
  let check_sleeping m = if Random.int 100 < cWAKE_UP_CHANCE && asleep m then 
        (wake_up m; add_update (Message(m.mspecies^" has woken up!")))
  and check_confused m = 
        if Random.int 100 < cSNAP_OUT_OF_CONFUSION && confused m then 
        (snap_out m; 
         add_update (Message(m.mspecies^" has snapped out of its confusion!")))
  and check_frozen m = if Random.int 100 < cDEFROST_CHANCE && frozen m then 
        (defrost m; add_update (Message(m.mspecies^" has unfrozen!")))
  and apply_poison m =
        if poisoned m then 
          (let dmg = cPOISON_DAMAGE *. float_of_int m.mmax_hp in
           let new_hp = if float_of_int m.mcurr_hp -. dmg < 0. then 0
                        else int_of_float (float_of_int m.mcurr_hp -. dmg) in
           m.mcurr_hp <- new_hp;
           add_update (Message(m.mspecies^" has been hurt by its poison!"))) in

  let (red_team, blue_team) = g in
  let (r_steammons, _) = red_team and (b_steammons, _) = blue_team in
  let red_req = ref None and blue_req = ref None in
  let set_request request r = request := Some (Request r) in
  let phase = ref (-1) in

  let handle_action action color =
    let req1 = match color with Blue -> blue_req | Red -> red_req and
        req2 = match color with Blue -> red_req | Red -> blue_req in
    let team1 = match color with Blue -> blue_team | Red -> red_team and
        team2 = match color with Blue -> red_team | Red -> blue_team in
    let (steammons1,minventory1) = team1 and (steammons2,minventory2) = team2 in
    match action with
    | SelectStarter name -> begin 
        switch_steammons steammons1 name;
        set_request req1 (ActionRequest (game_datafication g)) end
    | PickSteammon name -> begin
        add_steammon steammons1 steammon_list name color;
        if List.length !steammons1 = cNUM_PICKS &&
           List.length !steammons2 = cNUM_PICKS then begin
          set_request req1 (PickInventoryRequest (game_datafication g));
          set_request req2 (PickInventoryRequest (game_datafication g)) end
        else begin match List.length !steammons1 - List.length !steammons2 with
          | 1 -> set_request req2 (PickRequest (opposite_color color,
                                                game_datafication g,
                                                !attack_list,
                                                !steammon_list))
          | _ -> set_request req1 (PickRequest (color,
                                                game_datafication g,
                                                !attack_list,
                                                !steammon_list)) end end
    | PickInventory inventory -> begin
        pick_inventory minventory1 inventory;
        set_request req1 (StarterRequest (game_datafication g)) end
    | SwitchSteammon name -> begin
        switch_steammons steammons1 name;
        set_request req1 (ActionRequest (game_datafication g)) end
    | UseItem (item,name) -> begin
        use_item steammons1 minventory1 name item color;
        set_request req1 (ActionRequest (game_datafication g)) end
    | UseAttack attack -> begin
        let active = List.hd !steammons1 in
        check_sleeping active;
        check_confused active;
        if asleep active || frozen active then ()
        else use_attack steammons1 steammons2 attack color;
        set_request req1 (ActionRequest (game_datafication g)) end in
  begin match ra,ba with
  | Action r_action, Action b_action -> begin
      let new_phase = match r_action with
                      | PickSteammon x -> 0 | PickInventory x -> 1 | _ -> 2 in
      phase := new_phase;
      let do_red_first () = handle_action r_action Red; 
                            handle_action b_action Blue
      and do_blue_first () = handle_action b_action Blue; 
                             handle_action r_action Red in
      match r_action,b_action with
      | UseAttack r_attack, UseAttack b_attack -> begin
          let r_active = List.hd !r_steammons
          and b_active = List.hd !b_steammons in
          let r_speed = find_speed r_active and b_speed = find_speed b_active in
          let set_first c = add_update (SetFirstAttacker c) in
          if r_speed > b_speed then (set_first Red; do_red_first ())
          else if b_speed > r_speed then (set_first Blue; do_blue_first ())
          else if Random.int 100 < 50 then (set_first Red; do_red_first ()) 
          else (set_first Blue; do_blue_first ()) end
      | UseAttack r_attack, _ -> do_blue_first ()
      | _, UseAttack b_attack -> do_red_first ()
      | _ -> if Random.int 100 < 50 then do_red_first () else do_blue_first () end
  | Action a, _ -> begin
      begin match a with
      | PickSteammon x -> phase := 0
      | PickInventory x -> phase := 1
      | _ -> (phase := 2; 
              set_request blue_req (ActionRequest (game_datafication g))) end;
      handle_action a Red end
  | _, Action a -> begin
      begin match a with
      | PickSteammon x -> phase := 0
      | PickInventory x -> phase := 1
      | _ -> (phase := 2; 
              set_request red_req (ActionRequest (game_datafication g))) end;
      handle_action a Blue end
  | _ -> () end;
  begin match !phase with
  | 2 -> 
    let r_active = List.hd !r_steammons
    and b_active = List.hd !b_steammons in
    check_frozen r_active;
    check_frozen b_active;
    apply_poison r_active;
    apply_poison b_active;
    if r_active.mcurr_hp = 0 then 
      (set_request red_req (StarterRequest (game_datafication g));
       blue_req := None)
    else if b_active.mcurr_hp = 0 then
      (set_request blue_req (StarterRequest (game_datafication g));
       red_req := None)
  | _ -> () end;
  let helper acc x = if x.mcurr_hp = 0 then acc else false in
  let red_fainted = List.length !r_steammons = cNUM_PICKS &&
                    List.fold_left helper true !r_steammons and
      blue_fainted = List.length !b_steammons = cNUM_PICKS &&
                     List.fold_left helper true !b_steammons in
  let game_result = match (red_fainted,blue_fainted) with
                    | true,true -> Some Tie
                    | true,false -> Some (Winner Blue)
                    | false,true -> Some (Winner Red)
                    | _ -> None in
  (game_result, game_datafication g, !red_req, !blue_req)


(* Initializes a game *)
let init_game (() : unit) : game * color * attack list * steammon list = 
  (* Reads "attack.txt" and converts it into a list of attacks.
       Also fills in attack_list. *)
  let attack_lines = read_lines "attack.txt" in
  let make_attack acc line = 
    let attrs = wordify line in
    if List.length attrs <> 8 then failwith "Incorrect format: attack.txt"
    else let attack = {name = List.hd attrs;
                       element = type_of_string (List.nth attrs 1);
                       max_pp = int_of_string (List.nth attrs 2);
                       pp_remaining = int_of_string (List.nth attrs 2);
                       power = int_of_string (List.nth attrs 3);
                       accuracy = int_of_string (List.nth attrs 4);
                       crit_chance = int_of_string (List.nth attrs 5);
                       effect = (effect_of_num (int_of_string (List.nth attrs 6)),
                                 int_of_string (List.nth attrs 7))} in
    attack::acc in
  let attacks = List.fold_left make_attack [] (List.tl attack_lines) in
  attack_list := attacks;
  (* Reads "steammon.txt" and converts it into a list of steammon.
      Also fills in steammon_list. *)
  let steammon_lines = read_lines "steammon.txt" in
  let make_steammon acc line =
    let attrs = wordify line in
    let make_type str =
      match str with
      | "Nothing" -> None
      | _ -> Some (type_of_string str) in
    let find_attack str =
      let helper acc x = if x.name = str then Some x else acc in
      let attack = List.fold_left helper None attacks in
      match attack with 
      | None -> failwith "An invalid attack was entered in steammon.txt"
      | Some att -> att in 
    if List.length attrs <> 13 then failwith "Incorrect format: steammon.txt"
    else let steammon = {species = List.hd attrs;
                         curr_hp = int_of_string (List.nth attrs 1);
                         max_hp = int_of_string (List.nth attrs 1);
                         first_type = make_type (List.nth attrs 2);
                         second_type = make_type (List.nth attrs 3);
                         first_attack = find_attack (List.nth attrs 4);
                         second_attack = find_attack (List.nth attrs 5);
                         third_attack = find_attack (List.nth attrs 6);
                         fourth_attack = find_attack (List.nth attrs 7);
                         attack = int_of_string (List.nth attrs 8);
                         spl_attack = int_of_string (List.nth attrs 9);
                         defense = int_of_string (List.nth attrs 10);
                         spl_defense = int_of_string (List.nth attrs 11);
                         speed = int_of_string (List.nth attrs 12);
                         status = [];
                         mods = {attack_mod = 0;
                                 speed_mod = 0;
                                 defense_mod = 0;
                                 accuracy_mod = 0}} in
    steammon::acc in
  let steammons = List.fold_left make_steammon [] steammon_lines in
  steammon_list := steammons;
  (* Returns a game, a color (representing the team that gets to pick first),
     a list of attacks, and a list of steammon *)
  let make_team () = (ref [], [ref cNUM_ETHER;
                               ref cNUM_MAX_POTION;
                               ref cNUM_REVIVE;
                               ref cNUM_FULL_HEAL;
                               ref cNUM_XATTACK;
                               ref cNUM_XDEFENSE;
                               ref cNUM_XACCURACY;
                               ref cNUM_XSPEED]) in
  let red = make_team () and blue = make_team () in
  let first = if Random.int 100 < 50 then Red else Blue in
  add_update InitGraphics;
  send_updates ();
  ((red,blue), first, attacks, steammons)
