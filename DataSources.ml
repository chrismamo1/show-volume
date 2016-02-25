open Humane_re
open Lwt.Infix

type state = { status: string; volume: int array }

module type VolumeProvider = sig
  type audio_source
  type audio_sink

  val int_of_sink : audio_sink -> int
  val sink_of_int : int -> audio_sink

  val read_volume :
    [ `Source of audio_source | `Sink of audio_sink ] ->
    state option ->
    state Lwt.t
end

module Make (M : VolumeProvider)
  : VolumeProvider = struct
  type audio_source = M.audio_source
  type audio_sink = M.audio_sink

  let int_of_sink = M.int_of_sink
  let sink_of_int = M.sink_of_int

  let read_volume = M.read_volume
end

module FilthyPulse = Make(struct
  type audio_source = int

  type audio_sink = int

  let int_of_sink x = x

  let sink_of_int x = x

  let read_volume =
    let parse_pactl =
      (* prebuilding regular expressions for performance *)
      let sinks_matcher = Str.regexp "Sink #.*\n\\(\t+.*\n\\)+" in
      let states_matcher = Str.regexp "State: \\(.*\\)\n" in
      let volumes_matcher = Str.regexp "\tVolume: \\(.*\\)\n" in
      fun lines ->
        let sinks = Str.(find_matches sinks_matcher lines) in
        let states = List.map Str.(find_matches states_matcher) sinks in
        let volumes = (* gets the raw volume strings *)
          List.map Str.(find_matches volumes_matcher) sinks
          |> List.flatten
          |> List.map
              (fun str ->
                try
                  Scanf.(sscanf
                          str
                          "\tVolume: front-left: %d / %d%% / %f dB, front-right: %d / %d%% / %f dB"
                          (fun _ a _ _ b _ -> a,b))
                with exn -> 0, 0)
        in
        List.map2 (fun a b -> a,b) states volumes
    in
    let rec aux count nsink old_state =
      let count = count + 1 in
      let cmd = "", [|"pactl"; "list"; "sinks"|] in
      Lwt_process.pread cmd
      >>= fun lines ->
      let sinks = parse_pactl lines in
      let sink = List.nth sinks nsink in
      let (status :: _), (vol_lft, vol_rgt) = sink in
      let sink = { status; volume = [|vol_lft;vol_rgt|] } in
      match old_state with
      | None -> Lwt.return sink
      | Some v when count > 100 -> Lwt.return v (* so that overflow may be avoided *)
      | Some v ->
          if v = sink
          then Lwt_unix.sleep 0.125 >>= fun () -> aux count nsink old_state
          else Lwt.return sink
    in
    function
    | `Sink n ->
        fun old_state ->
          aux 0 n old_state
    | `Source _ -> raise (Failure "not yet implemented")
end)
