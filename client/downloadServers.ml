(* Copyright 2001, 2002 b8_bavard, b8_fee_carabine, INRIA *)
(*
    This file is part of mldonkey.

    mldonkey is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    mldonkey is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with mldonkey; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)
open Options
open Unix
open BasicSocket
open TcpBufferedSocket
open Mftp
open Files
open Mftp_comm
open DownloadTypes
open DownloadOptions
open DownloadComplexOptions
open DownloadGlobals
open Gui_types

let udp_send_if_possible sock addr msg =
  udp_send_if_possible sock upload_control addr msg
  
let first_name file =
  match file.file_filenames with
    [] -> Filename.basename file.file_hardname
  | name :: _ -> name
    
let last_connected_server () =
  match !servers_list with 
  | s :: _ -> s
  | [] -> 
      servers_list := 
      Hashtbl2.fold (fun key s l ->
          s :: l
      ) servers_by_key [];
      match !servers_list with
        [] -> raise Not_found
      | s :: _ -> s

let all_servers () =
  Hashtbl2.fold (fun key s l ->
      s :: l
  ) servers_by_key []


(****************************************************)
        
let update_options () =  
  known_servers =:=  Sort.list (fun s1 s2 -> 
      s1.server_score > s2.server_score ||
      (s1.server_score = s2.server_score &&
        (connection_last_conn 
            s1.server_connection_control) 
        > (connection_last_conn s2.server_connection_control))
  ) !!known_servers
  
let server_handler s sock event = 
  match event with
    BASIC_EVENT (CLOSED _) ->
      if s.server_sock <> None then decr nservers;

      (*
            Printf.printf "%s:%d CLOSED received by server"
(Ip.to_string s.server_ip) s.server_port; print_newline ();
  *)
      connection_failed (s.server_connection_control);
      s.server_sock <- None;
      s.server_score <- s.server_score - 1;
      s.server_users <- [];
      set_server_state s NotConnected;
      !server_is_disconnected_hook s
  | _ -> ()

let verify_ip sock =
(*  Printf.printf "VERIFY IP";  print_newline (); *)
  try
    incr ip_verified;
    let ip = TcpBufferedSocket.my_ip sock in
    if ip <> Ip.localhost  then begin
        Printf.printf "USING %s FOR CLIENT IP" (Ip.to_string ip);
        print_newline ();
        client_ip =:= ip;
        ip_verified := 10;
      end;
  with e -> 
      Printf.printf "Exception %s while verifying IP address"
        (Printexc.to_string e); print_newline ()
      
      
let client_to_server s t sock =
  if !ip_verified < 10 then verify_ip sock;
  let module M = Mftp_server in
  match t with
    M.SetIDReq t ->
      s.server_cid <- t;
      set_rtimeout (TcpBufferedSocket.sock sock) infinite_timeout;
      set_server_state s Connected_initiating;
      s.server_score <- s.server_score + 5;
      connection_ok (s.server_connection_control);

      direct_server_send sock (
        let module A = M.AckID in
        M.AckIDReq A.t
      );
      
      (*
      server_send sock (M.ShareReq (make_tagged (
            if !nservers <=  max_allowed_connected_servers () then
              begin
                s.server_master <- true;
                let shared_files = all_shared () in
                shared_files
              end else
              []
          )));
*)
      
  | M.ServerListReq l ->
      if !!update_server_list then
      let module Q = M.ServerList in
      List.iter (fun s ->
          if Ip.valid s.Q.ip && not (List.mem s.Q.ip !!server_black_list) then
            ignore (add_server s.Q.ip s.Q.port);
      ) l
  
  | M.ServerInfoReq t ->
      
      let module Q = M.ServerInfo in
(* query file locations *)
      s.server_score <- s.server_score + 1;
      s.server_tags <- t.Q.tags;
      List.iter (fun tag ->
          match tag with
            { tag_name = "name"; tag_value = String name } -> 
              s.server_name <- name
          | { tag_name = "description"; tag_value = String desc } ->
              s.server_description <- desc
          | _ -> ()
      ) s.server_tags;
      set_server_state s Connected_idle;
      !server_is_connected_hook s sock
  
  | M.InfoReq (users, files) ->
      s.server_nusers <- users;
      s.server_nfiles <- files;
      s.server_changed <- ServerBusyChange;
      !server_change_hook s
  | _ -> 
      !received_from_server_hook s sock t
      
let connect_server s =
  if can_open_connection () then
    try
(*                Printf.printf "CONNECTING ONE SERVER"; print_newline (); *)
      connection_try s.server_connection_control;
      s.server_cid <- !!client_ip;
      incr nservers;
      printf_char 's'; 
      let sock = TcpBufferedSocket.connect (
          Ip.to_inet_addr s.server_ip) s.server_port 
          (server_handler s) (* Mftp_comm.server_msg_to_string*)  in
      set_server_state s Connecting;
      TcpBufferedSocket.set_read_controler sock download_control;
      TcpBufferedSocket.set_write_controler sock upload_control;
      
      set_reader sock (Mftp_comm.server_handler
          (client_to_server s));
      set_rtimeout (TcpBufferedSocket.sock sock) !!server_connection_timeout;
      set_handler sock (BASIC_EVENT RTIMEOUT) (fun s ->
          close s "timeout"  
      );
      
      s.server_sock <- Some sock;
      direct_server_send sock (
        let module M = Mftp_server in
        let module C = M.Connect in
        M.ConnectReq {
          C.md4 = !!client_md4;
          C.ip = !!client_ip;
          C.port = !client_port;
          C.tags = !client_tags;
        }
      );
    with _ -> 
(*
      Printf.printf "%s:%d IMMEDIAT DISCONNECT "
      (Ip.to_string s.server_ip) s.server_port; print_newline ();
*)
(*      Printf.printf "DISCONNECTED IMMEDIATLY"; print_newline (); *)
        decr nservers;
        s.server_sock <- None;
        set_server_state s NotConnected;
        connection_failed s.server_connection_control
        
let rec connect_one_server () =
  if can_open_connection () then
    match !servers_list with
      [] ->
        
        servers_list := !!known_servers;
(*
      Hashtbl2.fold (fun key s l ->
          s :: l
) servers_by_key [];
  *)
        if !servers_list = [] then raise Not_found;
        connect_one_server ()
    | s :: list ->
        servers_list := list;
        if connection_can_try s.server_connection_control then
          begin
(* connect to server *)
            match s.server_sock with
              Some _ -> ()
            | None -> 
                if s.server_score < 0 then begin
(*                  Printf.printf "TOO BAD SCORE"; print_newline ();*)
                    connect_one_server ()
                  end
                else
                  connect_server s
          
          end
          

let force_check_server_connections user =
  if user || !nservers <     max_allowed_connected_servers ()  then begin
      if !nservers < !!max_connected_servers then
        begin
          for i = !nservers to !!max_connected_servers-1 do
            connect_one_server ();
          done;
        end
    end
    
let rec check_server_connections timer =
(*  Printf.printf "Check connections"; print_newline (); *)
  reactivate_timer timer;
  force_check_server_connections false

let remove_old_servers () =
  let list = ref [] in
  let min_last_conn =  last_time () -. 
    float_of_int !!max_server_age *. one_day in
  List.iter (fun s ->
      if connection_last_conn s.server_connection_control < min_last_conn ||
        List.mem s.server_ip !!server_black_list
      then
        begin
(*                  Printf.printf "*******  SERVER REMOVED ******"; 
                  print_newline (); *)
          set_server_state s  Removed;
        end else
        list := s :: !list
  ) !!known_servers;
  if List.length !list > 200 then begin
      servers_ini_changed := true;
      known_servers =:= List.rev !list
    end
  
let remove_old_servers_timer () = 
  if List.length !!known_servers > 1000 then
    remove_old_servers ()

(* Don't let more than max_allowed_connected_servers running for
more than 5 minutes *)
    
let update_master_servers _ =
(*  Printf.printf "update_master_servers"; print_newline (); *)
  let nmasters = ref 0 in
  List.iter (fun s ->
      if s.server_master then
        match s.server_sock with
          None -> ()
        | Some _ -> incr nmasters;
  ) !connected_server_list;
  let nconnected_servers = ref 0 in
  List.iter (fun s ->
      incr nconnected_servers;
      if not s.server_master then
        if !nmasters <  max_allowed_connected_servers () &&
          s.server_nusers >= !!master_server_min_users
        then begin
            match s.server_sock with
              None -> 
              (*  Printf.printf "MASTER NOT CONNECTED"; print_newline ();  *)
                ()
            | Some sock ->                
(*                Printf.printf "NEW MASTER SERVER"; print_newline (); *)
                s.server_master <- true;
                incr nmasters;
                direct_server_send sock (Mftp_server.ShareReq
                  (DownloadShare.make_tagged (DownloadShare.all_shared ())));
          end else
        if connection_last_conn s.server_connection_control 
            +. 120. < last_time () &&
          !nconnected_servers > max_allowed_connected_servers ()  then begin
(* remove one third of the servers every 5 minutes *)
            nconnected_servers := !nconnected_servers - 3;
(*            Printf.printf "DISCONNECT FROM EXTRA SERVER %s:%d "
(Ip.to_string s.server_ip) s.server_port; print_newline ();
  *)
            (match s.server_sock with
                None ->                   
                  (*
                  Printf.printf "Not connected !"; 
print_newline ();
*)
                  ()

              | Some sock ->
  (*                Printf.printf "shutdown"; print_newline (); *)
                  (shutdown sock "max allowed"));
          end
  ) 
  (* reverse the list, so that first servers to connect are kept ... *)
  (List.rev !connected_server_list)
    
(* Keep connecting to servers in the background. Don't stay connected to 
  them , and don't send your shared files list *)
let walker_list = ref []
let next_walker_start = ref 0.0
let walker_timer timer = 
  reactivate_timer timer;
  match !walker_list with
    [] ->
      if !!known_servers <> [] &&
        last_time () > !next_walker_start then begin
          walker_list := !!known_servers;
          next_walker_start := last_time () +. 4. *. 3600.;
        end
  | s :: tail ->
      walker_list := tail;
      match s.server_sock with
        None -> 
          if connection_can_try s.server_connection_control then
            connect_server s
      | Some _ -> ()