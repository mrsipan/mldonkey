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

type hash_method = MD4 | MD5 | SHA1

type job = {
    job_name : string;
    job_begin : int64;
    job_len : int64;
    job_method : hash_method;
    job_result : string;
    job_handler : (job -> unit);
  }

let fifo = Fifo.create ()
let current_job = ref None
  
external job_done : job -> bool = "ml_job_done"
external job_start : job -> Unix.file_descr -> unit = "ml_job_start"
  
let _ =
  BasicSocket.add_infinite_timer 1.0 (fun _ ->
      try
        match !current_job with
        | None -> raise Not_found
        | Some (job, fd) ->
            if job_done job then begin
                current_job := None;
                Unix.close fd;
                (try job.job_handler job with _ -> ());
                raise Not_found
              end
      with _ ->
          let job = Fifo.take fifo in
          let fd = Unix.openfile job.job_name [Unix.O_RDONLY] 0o444 in
          current_job := Some (job, fd);
          Printf.printf "Starting job %s %Ld %Ld" job.job_name
            job.job_begin job.job_len; print_newline ();
          job_start job fd
  )
  
let compute_md4 name begin_pos len f =
  let job = {
      job_name = name;
      job_begin = begin_pos;
      job_len = len;
      job_method = MD4;
      job_result = String.create 16;
      job_handler = f;
    } in
  Fifo.put fifo job
  
