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

let file_basedir = ""
let cmd_basedir = Autoconf.current_dir (* will not work on Windows *)

let directconnect_ini = create_options_file (file_basedir ^ "directconnect.ini")
  
  
let max_connected_servers = define_option directconnect_ini
  ["max_connected_servers"] 
    "The number of servers you want to stay connected to" int_option 10

let login_messages = define_option directconnect_ini
    ["login_messages"]
    "Some more messages to send to the server when connecting"
    (list_option string_option)
  ["$Version 1,0091"; "$GetNickList"]
  

let ip_cache_timeout = define_option directconnect_ini
    ["ip_cache_timeout"]
    "The time an ip address can be kept in the cache"
    float_option 3600.

let load_hublist = define_option directconnect_ini ["load_hublist"]
    "Download a list of servers"
    bool_option true

  
let shared_offset = define_option directconnect_ini
    ["shared_offset"]
    "An amount of bytes to add to the shared total (can help to connect)"
    float_option 10000000000.

  
let dc_port = define_option directconnect_ini ["client_port"]
  "The port to bind the client to"
    int_option 4444
  
let login = define_option directconnect_ini ["login"]
    "Your login on DC" string_option ""
  
    
let max_known_servers = define_option directconnect_ini
    ["query_hublist_limit"] 
    "The limit on the number of servers to avoid asking for a new list" int_option 100
